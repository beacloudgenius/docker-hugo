FROM ruby:2.5.3-alpine3.8

ENV ALPINE_VERSION=3.8

LABEL maintainer="nilesh@cloudgeni.us"

ENV HUGO_VERSION=0.51
ENV HUGO_DOWNLOAD_URL=https://github.com/spf13/hugo/releases/download/v${HUGO_VERSION}/hugo_${HUGO_VERSION}_Linux-64bit.tar.gz

RUN apk add --update --no-cache --virtual build-dependencies

RUN apk add --update --no-cache \
		bash \
		build-base \
		ca-certificates \
		curl \
		git \
		libcurl \
		libxml2-dev \
		libxslt-dev \
		openssh \
		rsync \
		wget && \
	gem install \
		html-proofer \
		nokogiri \
	--no-document && \
	apk del build-dependencies && \
	rm -rf /var/cache/apk/*

RUN wget "$HUGO_DOWNLOAD_URL" && \
	tar xzf hugo_${HUGO_VERSION}_Linux-64bit.tar.gz && \
	mv hugo /usr/bin/hugo && \
	rm hugo_${HUGO_VERSION}_Linux-64bit.tar.gz LICENSE README.md

RUN apk add --update nodejs nodejs-npm

RUN apk add --no-cache ca-certificates

ENV GOLANG_VERSION 1.10.5

# make-sure-R0-is-zero-before-main-on-ppc64le.patch: https://github.com/golang/go/commit/9aea0e89b6df032c29d0add8d69ba2c95f1106d9 (Go 1.9)
#COPY *.patch /go-alpine-patches/

RUN set -eux; \
	apk add --no-cache --virtual .build-deps \
		bash \
		gcc \
		musl-dev \
		openssl \
		go \
	; \
	export \
# set GOROOT_BOOTSTRAP such that we can actually build Go
		GOROOT_BOOTSTRAP="$(go env GOROOT)" \
# ... and set "cross-building" related vars to the installed system's values so that we create a build targeting the proper arch
# (for example, if our build host is GOARCH=amd64, but our build env/image is GOARCH=386, our build needs GOARCH=386)
		GOOS="$(go env GOOS)" \
		GOARCH="$(go env GOARCH)" \
		GOHOSTOS="$(go env GOHOSTOS)" \
		GOHOSTARCH="$(go env GOHOSTARCH)" \
	; \
# also explicitly set GO386 and GOARM if appropriate
# https://github.com/docker-library/golang/issues/184
	apkArch="$(apk --print-arch)"; \
	case "$apkArch" in \
		armhf) export GOARM='6' ;; \
		x86) export GO386='387' ;; \
	esac; \
	\
	wget -O go.tgz "https://golang.org/dl/go$GOLANG_VERSION.src.tar.gz"; \
	echo 'f0a3ed5c775f39a970d4937c64b3b178992e23a5df57ae56a59a1c99253094f4 *go.tgz' | sha256sum -c -; \
	tar -C /usr/local -xzf go.tgz; \
	rm go.tgz; \
	\
	cd /usr/local/go/src; \
	for p in /go-alpine-patches/*.patch; do \
		[ -f "$p" ] || continue; \
		patch -p2 -i "$p"; \
	done; \
	./make.bash; \
	\
	rm -rf /go-alpine-patches; \
	apk del .build-deps; \
	\
	export PATH="/usr/local/go/bin:$PATH"; \
	go version

ENV GOPATH /go
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH

RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"
WORKDIR $GOPATH

RUN go get -v github.com/bep/s3deploy





# Install needed packages. Notes:
#   * dumb-init: a proper init system for containers, to reap zombie children
#   * musl: standard C library
#   * lib6-compat: compatibility libraries for glibc
#   * linux-headers: commonly needed, and an unusual package name from Alpine.
#   * build-base: used so we include the basic development packages (gcc)
#   * bash: so we can access /bin/bash
#   * git: to ease up clones of repos
#   * ca-certificates: for SSL verification during Pip and easy_install
#   * python: the binaries themselves
#   * python-dev: are used for gevent e.g.
#   * py-setuptools: required only in major version 2, installs easy_install so we can install Pip.
ENV PACKAGES="\
  dumb-init \
  musl \
  libc6-compat \
  linux-headers \
  build-base \
  bash \
  git \
  ca-certificates \
  python2 \
  python2-dev \
  py-setuptools \
"

RUN echo \
  # replacing default repositories with edge ones
  && echo "http://dl-cdn.alpinelinux.org/alpine/v$ALPINE_VERSION/testing" > /etc/apk/repositories \
  && echo "http://dl-cdn.alpinelinux.org/alpine/v$ALPINE_VERSION/community" >> /etc/apk/repositories \
  && echo "http://dl-cdn.alpinelinux.org/alpine/v$ALPINE_VERSION/main" >> /etc/apk/repositories \
  # Add the packages, with a CDN-breakage fallback if needed
  && apk add --no-cache $PACKAGES || \
    (sed -i -e 's/dl-cdn/dl-4/g' /etc/apk/repositories && apk add --no-cache $PACKAGES) \
  # turn back the clock -- so hacky!
  && echo "http://dl-cdn.alpinelinux.org/alpine/v$ALPINE_VERSION/main/" > /etc/apk/repositories \
  # && echo "@community http://dl-cdn.alpinelinux.org/alpine/v$ALPINE_VERSION/community" >> /etc/apk/repositories \
  # && echo "@testing http://dl-cdn.alpinelinux.org/alpine/v$ALPINE_VERSION/testing" >> /etc/apk/repositories \
  # && echo "@edge-main http://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories \
  # make some useful symlinks that are expected to exist
  && if [[ ! -e /usr/bin/python ]];        then ln -sf /usr/bin/python2.7 /usr/bin/python; fi \
  && if [[ ! -e /usr/bin/python-config ]]; then ln -sf /usr/bin/python2.7-config /usr/bin/python-config; fi \
  && if [[ ! -e /usr/bin/easy_install ]];  then ln -sf /usr/bin/easy_install-2.7 /usr/bin/easy_install; fi \
  # Install and upgrade Pip
  && easy_install pip \
  && pip install --upgrade pip \
  && if [[ ! -e /usr/bin/pip ]]; then ln -sf /usr/bin/pip2.7 /usr/bin/pip; fi \
  && echo

RUN pip --no-cache-dir install awscli && rm -rf /var/cache/apk/*

RUN apk update && apk add jq && rm -rf /var/cache/apk/*

CMD ["htmlproofer","--help"]

EXPOSE 1313
