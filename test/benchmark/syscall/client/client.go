package main

import (
	"flag"
	"net"
	"syscall"

	"github.com/sirupsen/logrus"
)

func do(dstAddr net.IP, dstPort int) error {
	sock, err := syscall.Socket(syscall.AF_INET, syscall.SOCK_DGRAM, syscall.IPPROTO_IP)
	if err != nil {
		return err
	}
	ip := dstAddr.To4()
	dst := syscall.SockaddrInet4{
		Port: dstPort,
		Addr: [4]byte{ip[0], ip[1], ip[2], ip[3]},
	}
	err = syscall.Connect(sock, &dst)
	if err != nil {
		return err
	}

	err = syscall.Close(sock)
	if err != nil {
		return err
	}

	return nil
}

var (
	dstIPStr string
	dstPort  int
	tryNum   int
)

func main() {
	flag.StringVar(&dstIPStr, "dst-ip", "", "destination IP address")
	flag.IntVar(&dstPort, "dst-port", 0, "destination prt")
	flag.IntVar(&tryNum, "try-num", 1, "try num")

	flag.Parse()
	if flag.NArg() > 0 {
		flag.PrintDefaults()
		logrus.Fatal("Invalid command")
	}

	dstIP := net.ParseIP(dstIPStr)
	if dstIP == nil {
		logrus.Fatalf("failed to parse dst-ip: %s", dstIPStr)
	}

	logrus.Infof("dstIP=%s dstPort=%d tryNum=%d", dstIP.String(), dstPort, tryNum)

	for i := 0; i < tryNum; i++ {
		err := do(dstIP, dstPort)
		if err != nil {
			logrus.Fatalf("failed to do : %s dstIP=%s dstPort=%d", err, dstIP.String(), dstPort)
		}
	}

	logrus.Info("done")
}
