FROM postgres:14.2-alpine

SHELL ["/bin/bash", "-e", "-o", "pipefail", "-c"]

# copy backup script
COPY ./docker/postgresql/backup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/backup.sh
