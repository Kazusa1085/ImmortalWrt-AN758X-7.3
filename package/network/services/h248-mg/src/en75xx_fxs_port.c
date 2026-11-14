// SPDX-License-Identifier: GPL-2.0
/*
 * Minimal line-control port for the H.248 MG skeleton.
 * Commands are newline-delimited on stdin; replies are newline-delimited.
 */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include "en75xx_voice.h"

static int fd = -1;
static int last_hook = -1;

static void reply_ok(const char *what)
{
	printf("OK %s\n", what);
	fflush(stdout);
}

static int cmd_open(const char *path)
{
	if (fd >= 0)
		close(fd);
	fd = open(path, O_RDWR | O_NONBLOCK);
	if (fd < 0) {
		printf("ERR open %s: %s\n", path, strerror(errno));
		fflush(stdout);
		return -1;
	}
	reply_ok("open");
	return 0;
}

static int cmd_ring(int on)
{
	struct en75xx_voice_ring ring = {
		.enable = on ? 1 : 0,
		.cadence_on_ms = 1000,
		.cadence_off_ms = 4000,
	};

	if (fd < 0)
		return -1;
	if (ioctl(fd, EN75XX_VOICE_SET_RING, &ring) < 0) {
		printf("ERR ring: %s\n", strerror(errno));
		fflush(stdout);
		return -1;
	}
	reply_ok(on ? "ring-on" : "ring-off");
	return 0;
}

static void poll_hook(void)
{
	struct en75xx_voice_line_state st;

	if (fd < 0)
		return;
	if (ioctl(fd, EN75XX_VOICE_GET_STATE, &st) < 0)
		return;
	if ((int)st.hook != last_hook) {
		last_hook = st.hook;
		printf("EVENT hook=%u\n", st.hook);
		fflush(stdout);
	}
}

static int cmd_hook(void)
{
	struct en75xx_voice_line_state st;
	if (fd < 0)
		return -1;
	if (ioctl(fd, EN75XX_VOICE_GET_STATE, &st) < 0) {
		printf("ERR state: %s\n", strerror(errno));
		fflush(stdout);
		return -1;
	}
	printf("STATE hook=%u linefeed=%u ringing=%u faults=%u\n",
	       st.hook, st.linefeed, st.ringing, st.faults);
	fflush(stdout);
	return 0;
}

static int cmd_linefeed(const char *value)
{
	unsigned long lf = strtoul(value, NULL, 0);
	unsigned int v = (unsigned int)lf;

	if (fd < 0)
		return -1;
	if (ioctl(fd, EN75XX_VOICE_SET_LINEFEED, &v) < 0) {
		printf("ERR linefeed: %s\n", strerror(errno));
		fflush(stdout);
		return -1;
	}
	reply_ok("linefeed");
	return 0;
}

int main(void)
{
	char line[256];

	setvbuf(stdout, NULL, _IOLBF, 0);
	setvbuf(stdin, NULL, _IOLBF, 0);
	while (1) {
		struct pollfd pfd = { .fd = 0, .events = POLLIN };
		int ready = poll(&pfd, 1, 100);

		poll_hook();
		if (ready <= 0)
			continue;
		if (!fgets(line, sizeof(line), stdin))
			break;
		line[strcspn(line, "\r\n")] = 0;
		if (!strncmp(line, "OPEN ", 5))
			cmd_open(line + 5);
		else if (!strcmp(line, "HOOK"))
			cmd_hook();
		else if (!strncmp(line, "LINEFEED ", 9))
			cmd_linefeed(line + 9);
		else if (!strcmp(line, "RING ON"))
			cmd_ring(1);
		else if (!strcmp(line, "RING OFF"))
			cmd_ring(0);
		else if (!strcmp(line, "PING"))
			reply_ok("pong");
		else if (!strcmp(line, "QUIT"))
			break;
		else
			printf("ERR unknown command\n");
	}
	if (fd >= 0)
		close(fd);
	return 0;
}
