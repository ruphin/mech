FROM ruby:2.2
MAINTAINER Goffert van Gool "goffert@phusion.nl"

RUN mkdir /mech

RUN wget https://get.docker.io/builds/Linux/x86_64/docker-latest -O /usr/bin/docker \
		&& chmod +x /usr/bin/docker \
		&& wget https://get.docker.io/builds/Linux/x86_64/docker-1.9.0 -O /usr/bin/docker1.9 \
		&& chmod +x /usr/bin/docker1.9 \
		&& wget https://get.docker.io/builds/Linux/x86_64/docker-1.8.3 -O /usr/bin/docker1.8 \
		&& chmod +x /usr/bin/docker1.8 \
		&& wget https://get.docker.io/builds/Linux/x86_64/docker-1.7.1 -O /usr/bin/docker1.7 \
		&& chmod +x /usr/bin/docker1.7

ENTRYPOINT ["ruby", "/mech/bin/mech.rb"]

WORKDIR /mech

COPY bin /mech/bin
COPY lib /mech/lib
