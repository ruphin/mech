FROM ruby:2.2
MAINTAINER Goffert van Gool "goffert@phusion.nl"

RUN mkdir /mech

RUN wget https://get.docker.io/builds/Linux/x86_64/docker-latest -O /usr/bin/docker \
		&& chmod +x /usr/bin/docker

ENTRYPOINT ["ruby", "/mech/bin/mech.rb"]

WORKDIR /mech

COPY bin /mech/bin
COPY lib /mech/lib
