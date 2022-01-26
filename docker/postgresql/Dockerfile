FROM postgres:14.1-alpine

# copy backup script
COPY ./docker/postgresql/backup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/backup.sh
