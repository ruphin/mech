FROM ruby:2.2
MAINTAINER Goffert van Gool "goffert@phusion.nl"

RUN mkdir /mech

RUN curl -L  https://github.com/coreos/etcd/releases/download/v2.0.9/etcd-v2.0.9-linux-amd64.tar.gz \
		| tar xzf - \
		&& mv etcd-v2.0.9-linux-amd64/etcdctl /usr/bin/ \
		&& rm -rf etcd-v2.0.9-linux-amd64

RUN wget https://get.docker.io/builds/Linux/x86_64/docker-latest -O /usr/bin/docker \
		&& chmod +x /usr/bin/docker

ENTRYPOINT ["ruby", "/mech/bin/mech.rb"]

COPY bin /mech/bin
COPY lib /mech/lib
