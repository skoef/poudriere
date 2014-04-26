/*-
 * Copyright (c) 2014 Bryan Drewery <bdrewery@FreeBSD.org>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer
 *    in this position and unchanged.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR(S) ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR(S) BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#define _WITH_GETLINE
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

/**
 * Timestamp stdout with given format
 */
int
main(int argc, char **argv) {
	const char *format;
	time_t elapsed, start, now;
	char *line = NULL;
	char timestamp[50];
	size_t linecap, tlen;
	ssize_t linelen;
	struct tm *t;

	if (argc != 3) {
		fprintf(stderr, "Usage: timestamp <UTC starttime> <format>\n");
		exit(1);
	}

	start = (int)strtol(argv[1], (char **)NULL, 10);
	format = argv[2];
	linecap = 0;
	setlinebuf(stdout);

	while ((linelen = getline(&line, &linecap, stdin)) > 0) {
		now = time(NULL);
		elapsed = now - start;
		t = gmtime(&elapsed);
		tlen = strftime(timestamp, sizeof(timestamp), format, t);
		fwrite(timestamp, tlen, 1, stdout);
		fwrite(line, linelen, 1, stdout);
	}

	return 0;
}
