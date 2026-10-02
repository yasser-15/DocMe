# DocMe database image.
#
# Isolation contract: this image contains NO application code and NO schema.
# It is a plain PostGIS + pgvector server. Schema lives in
# supabase/migrations/ and is applied by the one-shot `migrate` service, so
# changing the schema never requires rebuilding this image.
#
# BASE IMAGE NOTE — this is load-bearing, do not change casually:
#   `postgis/postgis:16-3.4` and `:16-3.5` are both Debian bullseye, whose PGDG
#   apt repository (bullseye-pgdg) has been RETIRED and now 404s. Any `apt-get
#   update` against those tags fails with exit code 100, so neither pgvector nor
#   any other PGDG package can be installed on them.
#   `pgvector/pgvector:pg16` is Debian bookworm, has a live PGDG repo, and
#   already ships pgvector — so we layer PostGIS on top of it instead.
#   Bump with care: verify `apt-cache policy postgresql-16-postgis-3` still
#   resolves before changing the tag.

FROM pgvector/pgvector:pg16

# -scripts carries the SQL objects (spatial_ref_sys, typmod functions) that
# `CREATE EXTENSION postgis` depends on. Omitting it produces a confusing
# "extension postgis is not available" at CREATE EXTENSION time.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      postgresql-16-postgis-3 \
      postgresql-16-postgis-3-scripts \
 && rm -rf /var/lib/apt/lists/*

# Fail at image-build time rather than mysteriously at first connection.
RUN psql --version && ls /usr/share/postgresql/16/extension/vector.control

# Never bake credentials into the image. The compose stack passes these via the
# environment, and .env is gitignored.
ARG POSTGRES_DB=docme
ARG POSTGRES_USER=docme_app
ARG POSTGRES_PASSWORD=docme_app_local

ENV POSTGRES_DB=${POSTGRES_DB} \
    POSTGRES_USER=${POSTGRES_USER} \
    POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
    PGDATA=/var/lib/postgresql/data/pgdata

EXPOSE 5432