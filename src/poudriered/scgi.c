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

#include <stdlib.h>
#define _WITH_DPRINTF
#include <stdio.h>
#include <ctype.h>
#include <ucl.h>
#include <unistd.h>

#include "internal.h"


ucl_object_t *
scgi_parse(char *raw) {
	int l, pos, keylen, varlen;
	int *cnt;
	const char *err = NULL;
	char *walk;
	ucl_object_t *scgi, *header, *o;

	walk = raw;
	/* read length */
	while (*walk && isdigit(*walk))
		walk++;
	walk = '\0';

	l = strtonum(raw, 0, INT_MAX, &err);
	if (err != NULL)
		return (NULL);
	walk++;
	raw = walk;

	pos = 0;
	header = NULL;

	while (pos <= l) {
		if (*walk == '\0') {
			if (varlen == 0) {
				cnt = &varlen;
			} else {
				o = ucl_object_fromstring_common(raw + keylen + 1, varlen, UCL_STRING_PARSE_INT);
				header = ucl_object_insert_key(header, o, raw, keylen, false);
				cnt = &keylen;
				keylen = 0;
				varlen = 0;
				walk++;
				raw = walk;
			}
			continue;
		}
		(*cnt)++;
		walk++;
		pos++;
	}

	o = ucl_object_find_key(header, "CONTENT_LENGTH");
	if (o == NULL || o->type != UCL_INT) {
		ucl_object_unref(header);
		return (NULL);
	}
	struct ucl_parser *parser = NULL;
	ucl_object_t *obj;

	raw++;
	parser = ucl_parser_new(0);
	if (!ucl_parser_add_chunk(parser, (const unsigned char *)raw, ucl_object_toint(o))) {
		ucl_object_unref(header);
		return (NULL);
	}
	scgi = ucl_object_insert_key(NULL, header, "header", 6, false);
	scgi = ucl_object_insert_key(NULL, ucl_parser_get_object(parser), "data", 4, false);

	return (scgi);
}

void
scgi_send(int fd, unsigned char *data)
{
	dprintf(fd, "Status: 200 OK\r\n");
	dprintf(fd, "Content-Type: text/plain\r\n");
	dprintf(fd, "\r\n");
	dprintf(fd, "%s", data);
	close(fd);
}
