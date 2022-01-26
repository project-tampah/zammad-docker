#!/usr/bin/env bash

set -e

function check_zammad_ready {
  # first we wait 15 seconds to give some time to the init container
  sleep 15

  count=0
  until [ -f "${ZAMMAD_READY_FILE}" ]; do
    ((count = count + 1))

    if [ $(expr $count % 3) == "0" ]; then
      echo "waiting for init container to finish install or update..."
    fi

    sleep 10
  done
}

# zammad init
if [ "$1" = 'zammad-init' ]; then
  # install / update zammad
  test -f "${ZAMMAD_READY_FILE}" && rm "${ZAMMAD_READY_FILE}"
  rsync -a ${RSYNC_ADDITIONAL_PARAMS} --delete --exclude 'public/assets/images/*' --exclude 'storage/fs/*' "${ZAMMAD_TMP_DIR}/" "${ZAMMAD_DIR}"
  rsync -a ${RSYNC_ADDITIONAL_PARAMS} "${ZAMMAD_TMP_DIR}"/public/assets/images/ "${ZAMMAD_DIR}"/public/assets/images

  until (echo >/dev/tcp/"${POSTGRES_HOST}"/"${POSTGRES_PORT}") &>/dev/null; do
    echo "zammad railsserver waiting for postgresql server to be ready..."
    sleep 5
  done

  cd "${ZAMMAD_DIR}"

  # configure database
  # https://stackoverflow.com/questions/407523/escape-a-string-for-a-sed-replace-pattern
  ESCAPED_POSTGRES_PASS=$(echo "$POSTGRES_PASSWORD" | sed -e 's/[\/&]/\\&/g')
  sed -e "s#.*adapter:.*#  adapter: postgresql#g" -e "s#.*database:.*#  database: ${POSTGRES_DB}#g" -e "s#.*username:.*#  username: ${POSTGRES_USER}#g" -e "s#.*password:.*#  password: ${ESCAPED_POSTGRES_PASS}\\n  host: ${POSTGRES_HOST}\\n  port: ${POSTGRES_PORT}#g" <contrib/packager.io/database.yml.pkgr >config/database.yml

  # configure trusted proxies
  sed -i -e "s#config.action_dispatch.trusted_proxies =.*#config.action_dispatch.trusted_proxies = ${RAILS_TRUSTED_PROXIES}#" config/environments/production.rb

  # check if database exists / update to new version
  echo "initialising / updating database..."
  if ! (bundle exec rails r 'puts User.any?' 2>/dev/null | grep -q true); then
    if [ "${POSTGRE_DB_CREATE}" == "true" ]; then
      bundle exec rake db:create
    fi
    bundle exec rake db:migrate
    bundle exec rake db:seed

    # create autowizard.json on first install
    if [[ -n "$AUTOWIZARD_JSON" && `base64 -d <<<${AUTOWIZARD_JSON}` ]]; then
      echo "Saving autowizard json payload..."
      base64 -d <<<"${AUTOWIZARD_JSON}" >auto_wizard.json
    fi
  else
    bundle exec rails r "Cache.clear"
    bundle exec rake db:migrate
  fi

  echo "configuring elasticsearch..."
  if [ "${ELASTICSEARCH_ENABLED}" == "false" ]; then
    bundle exec rails r "Setting.set('es_url', '')"
  else
    bundle exec rails r "Setting.set('es_url', '${ELASTICSEARCH_SCHEMA}://${ELASTICSEARCH_HOST}:${ELASTICSEARCH_PORT}')"

    bundle exec rails r "Setting.set('es_index', '${ELASTICSEARCH_NAMESPACE}')"

    if [ -n "${ELASTICSEARCH_USER}" ] && [ -n "${ELASTICSEARCH_PASS}" ]; then
      bundle exec rails r "Setting.set('es_user', \"${ELASTICSEARCH_USER}\")"
      bundle exec rails r "Setting.set('es_password', \"${ELASTICSEARCH_PASS}\")"
    fi

    until (echo >/dev/tcp/${ELASTICSEARCH_HOST}/${ELASTICSEARCH_PORT}) &>/dev/null; do
      echo "zammad railsserver waiting for elasticsearch server to be ready..."
      sleep 5
    done

    if [ "${ELASTICSEARCH_SSL_VERIFY}" == "false" ]; then
      SSL_SKIP_VERIFY="-k"
    else
      SSL_SKIP_VERIFY=""
    fi

    if [ "${ELASTICSEARCH_REINDEX}" == "true" ]; then
      if ! curl -s "${SSL_SKIP_VERIFY}" "${ELASTICSEARCH_SCHEMA}://${ELASTICSEARCH_HOST}:${ELASTICSEARCH_PORT}/_cat/indices" | grep -q ${ELASTICSEARCH_NAMESPACE}; then
        echo "rebuilding elasticsearch index..."
        bundle exec rake searchindex:rebuild
      fi
    fi
  fi

  # create install ready file
  echo 'zammad-init' >"${ZAMMAD_READY_FILE}"
  echo "zammad init done!"
fi

# zammad nginx
if [ "$1" = 'zammad-nginx' ]; then
  check_zammad_ready

  # configure nginx
  sed -e "s#\(listen\)\(.*\)80#\1\2${NGINX_PORT}#g" \
    -e "s#proxy_set_header X-Forwarded-Proto .*;#proxy_set_header X-Forwarded-Proto ${NGINX_SERVER_SCHEME};#g" \
    -e "s#server .*:3000#server ${ZAMMAD_RAILSSERVER_HOST}:${ZAMMAD_RAILSSERVER_PORT}#g" \
    -e "s#server .*:6042#server ${ZAMMAD_WEBSOCKET_HOST}:${ZAMMAD_WEBSOCKET_PORT}#g" \
    -e "s#server_name .*#server_name ${NGINX_SERVER_NAME};#g" \
    -e 's#/var/log/nginx/zammad.\(access\|error\).log#/dev/stdout#g' <contrib/nginx/zammad.conf >/etc/nginx/sites-enabled/default

  echo "starting nginx..."
  exec /usr/sbin/nginx -g 'daemon off;'
fi

# zammad-railsserver
if [ "$1" = 'zammad-railsserver' ]; then
  test -f /opt/zammad/tmp/pids/server.pid && rm /opt/zammad/tmp/pids/server.pid

  check_zammad_ready

  cd "${ZAMMAD_DIR}"

  echo "starting railsserver... with WEB_CONCURRENCY=${ZAMMAD_WEB_CONCURRENCY}"
  exec bundle exec puma -b tcp://[::]:"${ZAMMAD_RAILSSERVER_PORT}" -w "${ZAMMAD_WEB_CONCURRENCY}" -e "${RAILS_ENV}"
fi

# zammad-scheduler
if [ "$1" = 'zammad-scheduler' ]; then
  check_zammad_ready

  cd "${ZAMMAD_DIR}"

  echo "starting scheduler..."
  exec bundle exec script/scheduler.rb run
fi

# zammad-websocket
if [ "$1" = 'zammad-websocket' ]; then
  check_zammad_ready

  cd "${ZAMMAD_DIR}"

  echo "starting websocket server..."
  exec bundle exec script/websocket-server.rb -b 0.0.0.0 -p "${ZAMMAD_WEBSOCKET_PORT}" start
fi
