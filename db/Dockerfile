FROM postgres:16-alpine

COPY migrations/ /docker-entrypoint-initdb.d/

COPY seed/900_seed.sql /docker-entrypoint-initdb.d/900_seed.sql

ARG WITH_SEED = 1

RUN if ["WITH_SEED" = "0"]; then rm /docker-entrypoint-initdb.d/900_seed.sql; fi \
&& chmod +x /docker-entrypoint-initdb.d/*.sh