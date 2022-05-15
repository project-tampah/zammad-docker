FROM elasticsearch:7.17.3

SHELL ["/bin/bash", "-e", "-o", "pipefail", "-c"]

RUN /usr/share/elasticsearch/bin/elasticsearch-plugin install --batch ingest-attachment
