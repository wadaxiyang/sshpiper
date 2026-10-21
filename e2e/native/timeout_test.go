//go:build (windows || darwin) && e2e

package native_test

import (
	"net"
	"sync"
	"testing"
	"time"

	"golang.org/x/crypto/ssh"
)

// Exercise issue #862 through the real daemon and fixed plugin. The upstream
// finishes authentication only after the downstream login grace time expires.
func testAuthenticationTimeoutCleanup(t *testing.T, s *nativeSuite) {
	lis, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	type attempt struct {
		release chan struct{}
		closed  chan struct{}
	}
	authStarted := make(chan attempt, 2)
	stop := make(chan struct{})
	var mu sync.Mutex
	var sockets []net.Conn
	var workers sync.WaitGroup
	workers.Add(1)
	go func() {
		defer workers.Done()
		for {
			conn, err := lis.Accept()
			if err != nil {
				return
			}
			mu.Lock()
			sockets = append(sockets, conn)
			mu.Unlock()
			workers.Add(1)
			go func() {
				defer workers.Done()
				defer conn.Close()
				current := attempt{release: make(chan struct{}), closed: make(chan struct{})}
				defer close(current.closed)
				config := &ssh.ServerConfig{PasswordCallback: func(_ ssh.ConnMetadata, password []byte) (*ssh.Permissions, error) {
					if string(password) == "slow" {
						authStarted <- current
						select {
						case <-current.release:
						case <-stop:
						}
					}
					return nil, nil
				}}
				config.AddHostKey(s.signer)
				server, channels, requests, err := ssh.NewServerConn(conn, config)
				if err != nil {
					return
				}
				defer server.Close()
				go ssh.DiscardRequests(requests)
				for channel := range channels {
					c, requests, err := channel.Accept()
					if err == nil {
						go ssh.DiscardRequests(requests)
						c.Close()
					}
				}
			}()
		}
	}()
	t.Cleanup(func() {
		close(stop)
		lis.Close()
		mu.Lock()
		for _, conn := range sockets {
			conn.Close()
		}
		mu.Unlock()
		workers.Wait()
	})

	piper := startDaemon(t, s.daemon, s.keyPath, []string{"SSHPIPERD_LOGIN_GRACE_TIME=2s"}, s.plugins["fixed"], "--target", lis.Addr().String())
	address := piper.waitReady(t)
	for i := 0; i < 2; i++ {
		result := make(chan error, 1)
		go func() {
			client, err := dialPiper(t, address, s.signer, "slow")
			if client != nil {
				client.Close()
			}
			result <- err
		}()
		var current attempt
		select {
		case current = <-authStarted:
		case <-time.After(waitTimeout):
			t.Fatal("upstream authentication never started")
		}
		select {
		case err := <-result:
			if err == nil {
				t.Fatal("downstream authenticated before the delayed upstream")
			}
		case <-time.After(waitTimeout):
			t.Fatal("login grace timeout did not disconnect downstream")
		}
		close(current.release)
		select {
		case <-current.closed:
		case <-time.After(5 * time.Second):
			t.Fatal("upstream connection leaked after downstream login timeout")
		}
	}
	// The same daemon must still establish a usable channel after the failures.
	client, err := dialPiper(t, address, s.signer, "pass")
	if err != nil {
		t.Fatal(err)
	}
	session, err := client.NewSession()
	if err != nil {
		t.Fatal(err)
	}
	session.Close()
	client.Close()
	piper.checkRunning(t)
}
