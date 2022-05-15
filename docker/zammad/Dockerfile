# note: zammad is currently incompatible to alpine because of:
# https://github.com/docker-library/ruby/issues/113
FROM ruby:2.7.4-slim AS builder

ARG BUILD_DATE
ARG DEBIAN_FRONTEND=noninteractive

ENV GIT_BRANCH stable
ENV GIT_URL ${PROJECT_URL}.git
ENV PROJECT_URL https://github.com/zammad/zammad
ENV RAILS_ENV production
ENV RAILS_LOG_TO_STDOUT true
ENV TAR_GZ_URL ${PROJECT_URL}/archive/${GIT_BRANCH}.tar.gz
ENV ZAMMAD_DIR /opt/zammad
ENV ZAMMAD_READY_FILE ${ZAMMAD_DIR}/tmp/zammad.ready
ENV ZAMMAD_TMP_DIR /tmp/zammad-${GIT_BRANCH}
ENV ZAMMAD_USER zammad

SHELL ["/bin/bash", "-e", "-o", "pipefail", "-c"]

# install zammad
COPY ./docker/zammad/setup.sh /tmp
RUN chmod +x /tmp/setup.sh && /tmp/setup.sh builder

FROM ruby:2.7.4-slim

ARG BUILD_DATE
ARG DEBIAN_FRONTEND=noninteractive

ENV GIT_BRANCH stable
ENV RAILS_ENV production
ENV RAILS_LOG_TO_STDOUT true
ENV ZAMMAD_DIR /opt/zammad
ENV ZAMMAD_READY_FILE ${ZAMMAD_DIR}/tmp/zammad.ready
ENV ZAMMAD_TMP_DIR /tmp/zammad-${GIT_BRANCH}
ENV ZAMMAD_USER zammad

COPY ./docker/zammad/setup.sh /tmp
RUN chmod +x /tmp/setup.sh && /tmp/setup.sh runner

COPY --from=builder ${ZAMMAD_TMP_DIR} ${ZAMMAD_TMP_DIR}
COPY --from=builder /usr/local/bundle /usr/local/bundle

# docker init
COPY ./docker/zammad/docker-entrypoint.sh /
RUN chmod +x /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

USER zammad

WORKDIR ${ZAMMAD_DIR}
