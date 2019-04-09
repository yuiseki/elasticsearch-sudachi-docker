# syntax = docker/dockerfile:1.0-experimental

ARG ELASTIC_VER=6.7.0
ARG ELASTIC_SUDACHI_VER=${ELASTIC_VER}-1.3.0
ARG SUDACHI_VER=0.2.1


######################################################################
# Sudachi本体のビルド. 辞書ビルドで、このjarが必要になる
######################################################################
FROM maven:3-jdk-8 as sudachi
RUN --mount=type=cache,target=/root/.m2 \
    git clone https://github.com/WorksApplications/Sudachi.git && \
    cd Sudachi && \
    mvn package -Dfile.encoding=UTF-8 

######################################################################
# Sudachiの辞書をビルドする.　ここは時間かかる
######################################################################
FROM maven:3-jdk-8 as sudachi-dic

# Heapを多めにとっておかないと、辞書をビルドするときOutOfMemoryに遭遇する
ENV MAVEN_OPTS=-Xmx4096m

ARG SUDACHI_VER

COPY --from=sudachi /Sudachi/target/sudachi-${SUDACHI_VER}-SNAPSHOT.jar /Sudachi/target/sudachi-${SUDACHI_VER}-SNAPSHOT.jar

RUN --mount=type=cache,target=/root/.m2 \
    curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash && \
    apt-get install git-lfs && \
    git lfs install && \
    : "sudachiのjarファイルをmavenに登録する" && \
    mvn install:install-file \
    -Dfile=/Sudachi/target/sudachi-${SUDACHI_VER}-SNAPSHOT.jar \
    -DgroupId=com.worksap.nlp \
    -DartifactId=sudachi \
    -Dversion=${SUDACHI_VER}-SNAPSHOT \
    -Dpackaging=jar \
    -DgeneratePom=true && \
    : "辞書をCloneしてビルドする" && \
    git clone https://github.com/WorksApplications/SudachiDict.git && \
    cd SudachiDict && git pull origin develop && \
    sed -i -e "s/0.1.2-SNAPSHOT/${SUDACHI_VER}-SNAPSHOT/g" pom.xml && \
    sed -i -e 's#</dependencies>#<dependency><groupId>com.worksap.nlp</groupId><artifactId>jdartsclone</artifactId><version>1.0.1</version></dependency></dependencies>#g' pom.xml && \
    mvn package -Dmaven.test.skip=true -Dfile.encoding=UTF-8 && \
    mkdir -p /sudachi-dic && \
    mv ./target/*.dic /sudachi-dic/

######################################################################
# elsaticsearch-sudachiをビルドする
######################################################################
FROM maven:3-jdk-8 as sudachi-plugin

ARG ELASTIC_VER
ARG ELASTIC_SUDACHI_VER
ENV ELASTIC_SUDACHI_FILENAME=analysis-sudachi-elasticsearch${ELASTIC_SUDACHI_VER}-SNAPSHOT.zip
ENV ELASTIC_SUDACHI_URL=https://github.com/WorksApplications/elasticsearch-sudachi/releases/download/v${ELASTIC_SUDACHI_VER}/${ELASTIC_SUDACHI_FILENAME}

RUN --mount=type=cache,target=/root/.m2 \
    git clone https://github.com/WorksApplications/elasticsearch-sudachi.git && \
    cd elasticsearch-sudachi && \
    git checkout -b worktag refs/tags/v${ELASTIC_SUDACHI_VER} && \
     sed -i -e "s#<artifactId>analysis-sudachi-elasticsearch.*</artifactId>#<artifactId>analysis-sudachi-elasticsearch${ELASTIC_VER}</artifactId>#g" pom.xml && \
    mvn package -Dmaven.test.skip=true && \
    mv ./target/releases /sudachi-plugin/

######################################################################
# Sudachiプラグインを入れたElasticsearchのイメージをビルドする
######################################################################
FROM docker.elastic.co/elasticsearch/elasticsearch:${ELASTIC_VER}

COPY --chown=elasticsearch:root --from=sudachi-dic /sudachi-dic/*.dic ./config/sudachi/
COPY --chown=elasticsearch:root --from=sudachi-plugin /sudachi-plugin/*.zip /tmp/elasticsearch/plugins/

ARG ELASTIC_SUDACHI_VER
ARG ELASTIC_SUDACHI_FILENAME=analysis-sudachi-elasticsearch${ELASTIC_SUDACHI_VER}.zip

RUN  bin/elasticsearch-plugin install -v  file:///tmp/elasticsearch/plugins/${ELASTIC_SUDACHI_FILENAME}

