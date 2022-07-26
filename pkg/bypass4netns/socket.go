package bypass4netns

import (
	"fmt"
	"syscall"
	"unsafe"

	"github.com/sirupsen/logrus"
)

type socketOption struct {
	level   uint64
	optname uint64
	optval  []byte
	optlen  uint64
}

type fcntlOption struct {
	cmd   uint64
	value uint64
}

type ioctlOption struct {
	req   uint64
	value []byte
}

type socketState int

const (
	// Bypassed means that the socket is replaced by one created on the host
	Bypassed socketState = iota

	// SwitchBacked means that the socket was bypassed but now rereplaced to the socket in netns.
	// This state can be hannpend in connect(2), sendto(2) and sendmsg(2)
	// when connecting to a host outside of netns and then connecting to a host inside of netns with same fd.
	SwitchBacked
)

type socketStatus struct {
	state     socketState
	fdInNetns int
	fdInHost  int
}

type socketInfo struct {
	options map[string][]socketOption
	fcntl   map[string][]fcntlOption
	ioctl   map[string][]ioctlOption
	status  map[string]socketStatus
}

// configureSocket set recorded socket options.
func (info *socketInfo) configureSocket(ctx *context, sockfd int) error {
	logrus.Debugf("configureSocket")
	key := fmt.Sprintf("%d:%d", ctx.req.Pid, ctx.req.Data.Args[0])
	optValues, ok := info.options[key]
	if !ok {
		return nil
	}
	for _, optVal := range optValues {
		_, _, errno := syscall.Syscall6(syscall.SYS_SETSOCKOPT, uintptr(sockfd), uintptr(optVal.level), uintptr(optVal.optname), uintptr(unsafe.Pointer(&optVal.optval[0])), uintptr(optVal.optlen), 0)
		if errno != 0 {
			return fmt.Errorf("setsockopt failed(%v): %s", optVal, errno)
		}
		logrus.Debugf("configured socket option pid=%d sockfd=%d (%v)", ctx.req.Pid, sockfd, optVal)
	}

	fcntlValues, ok := info.fcntl[key]
	if !ok {
		return nil
	}
	for _, fcntlVal := range fcntlValues {
		_, _, errno := syscall.Syscall(syscall.SYS_FCNTL, uintptr(sockfd), uintptr(fcntlVal.cmd), uintptr(fcntlVal.value))
		if errno != 0 {
			return fmt.Errorf("fnctl failed(%v): %s", fcntlVal, errno)
		}
		logrus.Debugf("configured socket fcntl pid=%d sockfd=%d (%v)", ctx.req.Pid, sockfd, fcntlVal)
	}

	ioctlValues, ok := info.ioctl[key]
	if !ok {
		return nil
	}
	for _, ioctlVal := range ioctlValues {
		_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, uintptr(sockfd), uintptr(ioctlVal.req), uintptr(unsafe.Pointer(&ioctlVal.value[0])))
		if errno != 0 {
			return fmt.Errorf("ioctl failed(%v): %s", ioctlVal, errno)
		}
		logrus.Debugf("configured socket ioctl pid=%d sockfd=%d (%v)", ctx.req.Pid, sockfd, ioctlVal)
	}

	return nil
}

// recordSocketOption records socket option.
func (info *socketInfo) recordSocketOption(ctx *context, logger *logrus.Entry) error {
	sockfd := ctx.req.Data.Args[0]
	level := ctx.req.Data.Args[1]
	optname := ctx.req.Data.Args[2]
	optlen := ctx.req.Data.Args[4]
	optval, err := readProcMem(ctx.req.Pid, ctx.req.Data.Args[3], optlen)
	if err != nil {
		return fmt.Errorf("readProcMem failed pid %v offset 0x%x: %s", ctx.req.Pid, ctx.req.Data.Args[1], err)
	}

	key := fmt.Sprintf("%d:%d", ctx.req.Pid, sockfd)
	_, ok := info.options[key]
	if !ok {
		info.options[key] = make([]socketOption, 0)
	}

	value := socketOption{
		level:   level,
		optname: optname,
		optval:  optval,
		optlen:  optlen,
	}
	info.options[key] = append(info.options[key], value)

	logger.Debugf("recorded socket option sockfd=%d level=%d optname=%d optval=%v optlen=%d", sockfd, level, optname, optval, optlen)
	return nil
}

// recordSocketOption records socket option.
func (info *socketInfo) recordFcntl(ctx *context, logger *logrus.Entry) error {
	sockfd := ctx.req.Data.Args[0]
	cmd := ctx.req.Data.Args[1]
	value := ctx.req.Data.Args[2]

	key := fmt.Sprintf("%d:%d", ctx.req.Pid, sockfd)
	_, ok := info.fcntl[key]
	if !ok {
		info.fcntl[key] = make([]fcntlOption, 0)
	}

	option := fcntlOption{
		cmd:   cmd,
		value: value,
	}
	info.fcntl[key] = append(info.fcntl[key], option)

	logger.Debugf("recorded fcntl sockfd=%d cmd=%d value=%d", sockfd, cmd, value)
	return nil
}

// recordSocketOption records socket option.
func (info *socketInfo) recordIoctl(ctx *context, logger *logrus.Entry) error {
	sockfd := ctx.req.Data.Args[0]
	req := ctx.req.Data.Args[1]
	value := ctx.req.Data.Args[2]

	key := fmt.Sprintf("%d:%d", ctx.req.Pid, sockfd)
	_, ok := info.ioctl[key]
	if !ok {
		info.ioctl[key] = make([]ioctlOption, 0)
	}

	buf, err := readProcMem(ctx.req.Pid, value, 4)
	if err != nil {
		return err
	}

	option := ioctlOption{
		req:   req,
		value: buf,
	}
	info.ioctl[key] = append(info.ioctl[key], option)

	logger.Debugf("recorded ioctl sockfd=%d req=%d value=%d", sockfd, req, value)
	return nil
}

// deleteSocketOptions delete recorded socket options and status
func (info *socketInfo) deleteSocket(ctx *context, logger *logrus.Entry) {
	sockfd := ctx.req.Data.Args[0]
	key := fmt.Sprintf("%d:%d", ctx.req.Pid, sockfd)
	_, ok := info.options[key]
	if ok {
		delete(info.options, key)
		logger.Debugf("removed socket options")
	}

	status, ok := info.status[key]
	if ok {
		delete(info.status, key)
		syscall.Close(status.fdInHost)
		syscall.Close(status.fdInHost)
		logger.Debugf("removed socket status(fdInNetns=%d fdInHost=%d)", status.fdInNetns, status.fdInHost)
	}
}
