/*-
 * Copyright (c) 2014 Baptiste Daroussin <bapt@FreeBSD.org>
 * All rights reserved.
 *~
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer
 *    in this position and unchanged.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *~
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

#include <sys/stat.h>
#include <sys/types.h>
#include <sys/param.h>

#include <fcntl.h>
#include <dirent.h>
#include <unistd.h>

#include "internal.h"

extern int conffd;

ucl_object_t *
ports_list(void)
{
	struct dirent *dp;
	int portfd;
	DIR *dirp;
	ucl_object_t *ports = NULL;
	ucl_object_t *o;
	char path[MAXPATHLEN];
	char *buf = NULL;
	size_t sz = 0;

	portfd = openat(conffd, "ports", O_RDONLY|O_DIRECTORY);
	if (portfd == -1)
		return (NULL);

	dirp = fdopendir(portfd);

	while ((dp = readdir(dirp)) != NULL) {
		o = NULL;
		if (!strcmp(dp->d_name, ".") || !strcmp(dp->d_name, ".."))
			continue;

		snprintf(path, sizeof(path), "%s/method", dp->d_name);
		if (!read_line_at(portfd, path, &buf, &sz)) {
			ucl_object_unref(o);
			continue;
		}
		o = ucl_object_insert_key(o,
		    ucl_object_fromstring_common(buf, strlen(buf), UCL_STRING_TRIM),
		    "method", 6, false);

		snprintf(path, sizeof(path), "%s/mnt", dp->d_name);
		if (!read_line_at(portfd, path, &buf, &sz)) {
			ucl_object_unref(o);
			continue;
		}
		o = ucl_object_insert_key(o,
		    ucl_object_fromstring_common(buf, strlen(buf), UCL_STRING_TRIM),
		    "mnt", 3, false);

		/* Not mandatory */
		snprintf(path, sizeof(path), "%s/fs", dp->d_name);
		if (read_line_at(portfd, path, &buf, &sz)) {
			o = ucl_object_insert_key(o,
			    ucl_object_fromstring_common(buf, strlen(buf), UCL_STRING_TRIM),
			    "fs", 2, false);
		}

		ports = ucl_object_insert_key(ports, o, dp->d_name, dp->d_namlen, false);
	}

	if (sz > 0)
		free(buf);

	closedir(dirp);

	return (ports);
}
