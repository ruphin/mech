FROM alpine:3.3
MAINTAINER Goffert van Gool "goffert@phusion.nl"


RUN mkdir /mech


RUN apk --update add ruby ruby-json wget ca-certificates \
		&& wget https://get.docker.io/builds/Linux/x86_64/docker-latest -O /usr/bin/docker \
		&& chmod +x /usr/bin/docker \
		&& wget https://get.docker.io/builds/Linux/x86_64/docker-1.9.1 -O /usr/bin/docker1.9 \
		&& chmod +x /usr/bin/docker1.9 \
		&& wget https://get.docker.io/builds/Linux/x86_64/docker-1.8.3 -O /usr/bin/docker1.8 \
		&& chmod +x /usr/bin/docker1.8

ENTRYPOINT ["ruby", "/mech/bin/mech.rb"]

WORKDIR /mech

COPY bin /mech/bin
COPY lib /mech/lib
