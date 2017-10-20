#!/bin/bash

if [ "${POSTGRES_DATABASE}" = "**None**" ]; then
  echo "You need to set the POSTGRES_DATABASE environment variable."
  exit 1
fi

if [ "${POSTGRES_HOST}" = "**None**" ]; then
  if [ -n "${POSTGRES_PORT_5432_TCP_ADDR}" ]; then
    POSTGRES_HOST=$POSTGRES_PORT_5432_TCP_ADDR
    POSTGRES_PORT=$POSTGRES_PORT_5432_TCP_PORT
  else
    echo "You need to set the POSTGRES_HOST environment variable."
    exit 1
  fi
fi

if [ "${POSTGRES_USER}" = "**None**" ]; then
  echo "You need to set the POSTGRES_USER environment variable."
  exit 1
fi

if [ "${POSTGRES_PASSWORD}" = "**None**" ]; then
  echo "You need to set the POSTGRES_PASSWORD environment variable or link to a container named POSTGRES."
  exit 1
fi

if [ -n $POSTGRES_PASSWORD ]; then
    export PGPASSWORD=$POSTGRES_PASSWORD
fi

if [ "$1" == "backup" ]; then
    if [ -n "$2" ]; then
        databases=$2
    else
        databases=`psql --username=$POSTGRES_USER --host=$POSTGRES_HOST --port=$POSTGRES_PORT -l | grep "UTF8" | awk '{print $1}'`
    fi

    for db in $databases; do
        echo "dumping $db"

        pg_dump --host=$POSTGRES_HOST --port=$POSTGRES_PORT --username=$POSTGRES_USER $db | gzip > "/tmp/$db.gz"

        if [ $? == 0 ]; then
            /usr/local/bin/azure storage blob upload /tmp/$db.gz $AZURE_STORAGE_CONTAINER -c "DefaultEndpointsProtocol=https;BlobEndpoint=https://$AZURE_STORAGE_ACCOUNT.blob.core.windows.net/;AccountName=$AZURE_STORAGE_ACCOUNT;AccountKey=$AZURE_STORAGE_ACCESS_KEY"

            if [ $? == 0 ]; then
                rm /tmp/$db.gz
            else
                >&2 echo "couldn't transfer $db.gz to Azure"
            fi
        else
            >&2 echo "couldn't dump $db"
        fi
    done
elif [ "$1" == "restore" ]; then
    if [ -n "$2" ]; then
        archives=$2.gz
    else
        archives=`/usr/local/bin/azure storage blob list -a $AZURE_STORAGE_ACCOUNT -k "$AZURE_STORAGE_ACCESS_KEY" $AZURE_STORAGE_CONTAINER | grep ".gz" | awk "{print $2}"`
    fi

    for archive in $archives; do
        tmp=/tmp/$archive

        echo "restoring $archive"
        echo "...transferring"

        /usr/local/bin/azure storage blob download  -a $AZURE_STORAGE_ACCOUNT -k "$AZURE_STORAGE_ACCESS_KEY" $AZURE_STORAGE_CONTAINER $archive $tmp

        if [ $? == 0 ]; then
            echo "...restoring"
            db=`basename --suffix=.gz $archive`

            psql --host=$POSTGRES_HOST --port=$POSTGRES_PORT --username=$POSTGRES_USER -d $db -c "drop schema public cascade; create schema public;"

            psql --host=$POSTGRES_HOST --port=$POSTGRES_PORT --username=$POSTGRES_USER -d $db
            gunzip -c $tmp | psql --host=$POSTGRES_HOST --port=$POSTGRES_PORT --username=$POSTGRES_USER -d $db
        else
            rm $tmp
        fi
    done
else
    >&2 echo "You must provide either backup or restore to run this container"
    exit 64
fi
