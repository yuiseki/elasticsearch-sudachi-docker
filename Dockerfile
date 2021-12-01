
ARG ELASTIC_VER=7.15.1
ARG ELASTIC_SUDACHI_VER=${ELASTIC_VER}-2.1.1
ARG ELASTIC_SUDACHI_FILENAME=analysis-sudachi-${ELASTIC_SUDACHI_VER}-SNAPSHOT.zip

######################################################################
# elsaticsearch-sudachiプラグインをビルドする
######################################################################
FROM gradle:jdk8 as sudachi-plugin

ARG ELASTIC_VER

RUN git clone --depth 1 https://github.com/WorksApplications/elasticsearch-sudachi.git && \
    cd elasticsearch-sudachi && \
    ./gradlew -PelasticsearchVersion=${ELASTIC_VER} build && \
    mv ./build/distributions /sudachi-plugin/


######################################################################
# Sudachi辞書とelsaticsearch-sudachiプラグインを入れたElasticsearchのイメージをビルドする
######################################################################
FROM docker.elastic.co/elasticsearch/elasticsearch:${ELASTIC_VER}

ARG ELASTIC_SUDACHI_FILENAME

RUN curl -OL http://sudachi.s3-website-ap-northeast-1.amazonaws.com/sudachidict/sudachi-dictionary-latest-core.zip && \
    curl -OL http://sudachi.s3-website-ap-northeast-1.amazonaws.com/sudachidict/sudachi-dictionary-latest-full.zip && \
    unzip -o -d config/sudachi -j 'sudachi-dictionary*.zip'  && \
    rm -f sudachi-dictionary*.zip

COPY --chown=elasticsearch:root --from=sudachi-plugin /sudachi-plugin/*.zip /tmp/elasticsearch/plugins/

RUN  bin/elasticsearch-plugin install -v  file:///tmp/elasticsearch/plugins/${ELASTIC_SUDACHI_FILENAME}

