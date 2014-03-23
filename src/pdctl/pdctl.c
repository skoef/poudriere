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

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/sbuf.h>

#include <string.h>
#include <unistd.h>
#include <ucl.h>
#include <err.h>
#include <getopt.h>

int
main(int argc, char **argv)
{
	struct sockaddr_un un;
	struct ucl_parser *parser = NULL;
	ucl_object_t *conf, *sock_path_o;
	int pdfd, ch;
	size_t r;
	const char *method, *uri, *data;
	struct sbuf *header, *req;
	char buf[BUFSIZ];

	struct option longopts[] = {
		{ "method", required_argument, NULL, 'm' },
		{ "uri", required_argument, NULL, 'u' },
		{ "data", required_argument, NULL, 'd' }
	};

	method = uri = data = NULL;

	while ((ch = getopt_long(argc, argv, "m:u:d:", longopts, NULL)) != -1) {
		switch (ch) {
		case 'm':
			method = optarg;
			break;
		case 'u':
			uri = optarg;
			break;
		case 'd':
			data = optarg;
			break;
		default:
			err(EXIT_FAILURE, "TODO\n");
		}
	}

	if (method == NULL)
		method = "GET";

	if (data == NULL)
		data = "";

	if (strcmp(method, "GET") != 0 &&
	    strcmp(method, "POST") != 0 &&
	    strcmp(method, "DELETE") != 0)
		err(EXIT_FAILURE, "the only valid method are: 'GET', 'POST', 'DELETE'");

	if (uri == NULL)
		uri = "/";

	if (*uri != '/')
		err(EXIT_FAILURE, "The uri should start with a '/'");

	parser = ucl_parser_new(UCL_PARSER_KEY_LOWERCASE);
	if (!ucl_parser_add_file(parser, PREFIX"/etc/poudriered.conf")) {
		errx(EXIT_FAILURE, "Failed to parse configuration file: %s",
		    ucl_parser_get_error(parser));
	}

	conf = ucl_parser_get_object(parser);
	ucl_parser_free(parser);

	if ((sock_path_o = ucl_object_find_key(conf, "socket")) == NULL) {
		warnx("'socket' not found in the configuration file");
		ucl_object_unref(conf);
		return (EXIT_FAILURE);
	}

	memset(&un, 0, sizeof(struct sockaddr_un));
	if ((pdfd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) {
		ucl_object_unref(conf);
		err(EXIT_FAILURE, "socket()");
	}

	un.sun_family = AF_UNIX;
	strlcpy(un.sun_path, ucl_object_tostring(sock_path_o),
	    sizeof(un.sun_path));

	if (connect(pdfd, (struct sockaddr *)&un,
	    sizeof(struct sockaddr_un)) == -1) {
		ucl_object_unref(conf);
		err(EXIT_FAILURE, "connect()");
	}

	header = sbuf_new_auto();
	sbuf_cat(header, "CONTENT_LENGTH");
	sbuf_putc(header, '\0');
	sbuf_printf(header, "%lu", data == NULL ? 0 : strlen(data));
	sbuf_putc(header, '\0');
	sbuf_cat(header, "SCGI");
	sbuf_putc(header, '\0');
	sbuf_putc(header, '1');
	sbuf_putc(header, '\0');
	sbuf_cat(header, "REQUEST_METHOD");
	sbuf_putc(header, '\0');
	sbuf_cat(header, method);
	sbuf_putc(header, '\0');
	sbuf_cat(header, "REQUEST_URI");
	sbuf_putc(header, '\0');
	sbuf_cat(header, uri);
	sbuf_putc(header, '\0');
	sbuf_finish(header);

	req = sbuf_new_auto();
	sbuf_printf(req, "%zd:", sbuf_len(header));
	sbuf_bcat(req, sbuf_data(header), sbuf_len(header));
	sbuf_printf(req, ",");
	sbuf_cat(req, data);
	sbuf_finish(req);

	write(pdfd, sbuf_data(req), sbuf_len(req));

	while ((r = read(pdfd, buf, BUFSIZ)) > 0) {
		write(fileno(stdout), buf, r);
	}
	printf("\n");

	return (EXIT_SUCCESS);
}
