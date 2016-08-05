FROM alpine:3.3
MAINTAINER Goffert van Gool "goffert@phusion.nl"

RUN mkdir /mech

RUN apk add --no-cache --virtual .docker tar curl ca-certificates \
	&& curl https://get.docker.com/builds/Linux/x86_64/docker-latest.tgz | tar -xz docker/docker --strip-components=1 \
	&& mv docker /usr/bin/docker \
	&& curl https://get.docker.com/builds/Linux/x86_64/docker-1.11.2.tgz | tar -xz docker/docker --strip-components=1 \
	&& mv docker /usr/bin/docker1.11 \
	&& curl https://get.docker.com/builds/Linux/x86_64/docker-1.10.3.tgz | tar -xz usr/local/bin/docker --strip-components=3 \
	&& mv docker /usr/bin/docker1.10 \
	&& curl https://get.docker.com/builds/Linux/x86_64/docker-1.9.1.tgz | tar -xz usr/local/bin/docker --strip-components=3 \
	&& mv docker /usr/bin/docker1.9 \
	&& apk del .docker \
	&& apk add --no-cache ruby ruby-json

ENTRYPOINT ["ruby", "/mech/bin/mech.rb"]

WORKDIR /mech

COPY bin /mech/bin
COPY lib /mech/lib
