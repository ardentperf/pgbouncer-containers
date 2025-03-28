# vim:set ft=dockerfile:
#
# Copyright The CloudNativePG Contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
ARG DEBIAN_VERSION=bookworm-20250317-slim
ARG PGBOUNCER_VERSION=1.24.0

FROM debian:${DEBIAN_VERSION} AS build
ARG PGBOUNCER_VERSION
WORKDIR /tmp

# Install build dependencies.
RUN set -ex; \
    apt-get update && apt-get upgrade -y; \
    apt-get install -y --no-install-recommends curl make pkg-config libevent-dev build-essential libssl-dev libudns-dev openssl python3 python3-pip python3-venv pandoc postgresql ; \
    apt-get purge -y --auto-remove ; \
    rm -fr /tmp/* ; \
    rm -rf /var/lib/apt/lists/*

RUN usermod -u 26 postgres
USER 26

# build pgbouncer
#
# this dockerfile was used for testing a local copy of pgbouncer from source. not an ideal or clean approache, but it works.
# > gh repo clone pgbouncer/pgbouncer
# > cd pgbouncer
# > git submodule init
# > git submodule update
# > ./autogen.sh
# > cd ..
# > tar czvf pgbouncer-containers/pgbouncer.tar.gz pgbouncer/
#
# > cd pgbouncer-containers
# > docker build . --target test
#
COPY pgbouncer.tar.gz .
RUN  tar xzf pgbouncer.tar.gz ; \
     cd pgbouncer ; \
     sh ./configure --without-cares --with-udns ;  \
     make

FROM build AS test
WORKDIR /tmp/pgbouncer

RUN set -ex; \
    python3 -m venv /tmp/venv

ENV PATH="/tmp/venv/bin:/usr/lib/postgresql/15/bin/:$PATH"

RUN set -ex; \
    pip3 install -Ur requirements.txt ; \
    pytest -n auto

FROM debian:${DEBIAN_VERSION}
ARG DEBIAN_VERSION
ARG PGBOUNCER_VERSION
ARG TARGETARCH

LABEL name="PgBouncer Container Images" \
      vendor="The CloudNativePG Contributors" \
      version="1.24.0" \
      release="12" \
      summary="Container images for PgBouncer (connection pooler for PostgreSQL)." \
      description="This Docker image contains PgBouncer based on Debian ${DEBIAN_VERSION}."

RUN  set -ex; \
     apt-get update && apt-get upgrade -y; \
     apt-get install -y libevent-dev libssl-dev libudns-dev libvshadow-utils findutils; \
     apt-get -y install postgresql ; \
     apt-get -y clean ; \
     rm -rf /var/lib/apt/lists/*; \
     rm -fr /tmp/* ; \
     groupadd -r --gid 996 pgbouncer ; \
     useradd -r --uid 998 --gid 996 pgbouncer ; \
     mkdir -p /var/log/pgbouncer ; \
     mkdir -p /var/run/pgbouncer ; \
     chown pgbouncer:pgbouncer /var/log/pgbouncer ; \
     chown pgbouncer:pgbouncer /var/run/pgbouncer ;

COPY --from=build ["/tmp/pgbouncer/pgbouncer", "/usr/bin/"]
COPY --from=build ["/tmp/pgbouncer/etc/pgbouncer.ini", "/etc/pgbouncer/pgbouncer.ini.example"]
COPY --from=build ["/tmp/pgbouncer/etc/userlist.txt", "/etc/pgbouncer/userlist.txt.example"]

RUN touch /etc/pgbouncer/pgbouncer.ini /etc/pgbouncer/userlist.txt

# DoD 2.3 - remove setuid/setgid from any binary that not strictly requires it, and before doing that list them on the stdout
RUN find / -not -path "/proc/*" -perm /6000 -type f -exec ls -ld {} \; -exec chmod a-s {} \; || true

EXPOSE 6432
USER pgbouncer

COPY entrypoint.sh .

ENTRYPOINT ["./entrypoint.sh"]
