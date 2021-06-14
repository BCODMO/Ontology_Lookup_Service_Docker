FROM ubuntu:16.04

#MASHUP of 
# 1) https://github.com/EBISPOT/OLS-docker/blob/master/Dockerfile
# 2) https://github.com/simonjupp/ols-docker/blob/master/Dockerfile

RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 7F0CEB10
RUN echo 'deb http://downloads-distro.mongodb.org/repo/ubuntu-upstart dist 10gen' | tee /etc/apt/sources.list.d/mongodb.list
RUN apt-get update && apt-get install -y \
		openjdk-8-jdk \
		maven \
		tomcat7 \
		mongodb-org \
		software-properties-common \
		wget \
		git \
		nano
        
ENV OLS_HOME /opt/ols/
ENV JAVA_OPTS "-Xmx1g"
#ENV CATALINA_OPTS "-Xms2g -Xmx2g"

ENV SOLR_VERSION 5.5.3

ADD ./ontologies/*.owl ${OLS_HOME}
ADD ols-config.yaml ${OLS_HOME}

## The install_solr_service.sh version from solr 5.5.3 has an issue with certain docker configurations
## Therefor we use the script of solr 6.3.0.  solr 6.3.0 is not compatible with OLS 
ADD 630_install_solr_service.sh /tmp/install_solr_service.sh

## Prepare MongoDB directories
RUN mkdir /data/ 
RUN mkdir /data/db 

## Clone GIT repository - has the BCO-DMOO specific ols-web
RUN git clone https://github.com/BCODMO/Ontology_Lookup_Service_Web.git /opt/OLS

### Install and stop solr 
RUN cd /opt \
  && wget http://archive.apache.org/dist/lucene/solr/${SOLR_VERSION}/solr-${SOLR_VERSION}.tgz \
	#&& tar xzf solr-${SOLR_VERSION}.tgz solr-${SOLR_VERSION}/bin/install_solr_service.sh --strip-components=2 \
	&& cp /tmp/install_solr_service.sh /opt/install_solr_service.sh \
  && bash ./install_solr_service.sh solr-${SOLR_VERSION}.tgz \
	&& service solr stop 

## Prepare configuration files
## Append ols.home property to file
RUN sed -i '$a ols.home /opt/OLS' /opt/OLS/ols-web/src/main/resources/application.properties 
## Comment out line 6
RUN sed -i '6 s/^/#/' /opt/OLS/ols-apps/ols-config-importer/src/main/resources/application.properties 

## Maven build 
RUN cd /opt/OLS/ \
	&& mvn clean install -Dols.home=/opt/OLS 

## Start MongoDB and
### Load configuration into MongoDB
RUN mongod --smallfiles --fork  --logpath /var/log/mongodb.log \
    && cd ${OLS_HOME} \
    && java -Dols.ontology.config=file://${OLS_HOME}/ols-config.yaml -jar ${OLS_HOME}/ols-config-importer.jar \
    && sleep 10
    
## Start MongoDB and SOLR
## Build/update the indexes
RUN mongod --smallfiles --fork --logpath /var/log/mongodb.log \
  && /opt/solr-${SOLR_VERSION}/bin/solr -Dsolr.solr.home=${OLS_HOME}/solr-5-config/ -Dsolr.data.dir=${OLS_HOME} \
  && java ${JAVA_OPTS} -Dols.home=${OLS_DATA} -jar ${OLS_HOME}/ols-indexer.jar

## Copy webapp to tomcat dir, replace the ROOT webapplication with boot-ols.war and set permissions
#RUN rm -R /var/lib/tomcat7/webapps/ROOT/
#RUN cp /opt/OLS/ols-web/target/ols-boot.war /var/lib/tomcat7/webapps/ROOT.war
#RUN chown -R tomcat7:tomcat7 /opt/OLS/

## Expose the tomcat port
EXPOSE 8080

CMD cd ${OLS_HOME} \
    && mongod --smallfiles --fork --logpath /var/log/mongodb.log \
    && /opt/solr-${SOLR_VERSION}/bin/solr -Dsolr.solr.home=${OLS_HOME}/solr-5-config/ -Dsolr.data.dir=${OLS_HOME} \
    && java -jar -Dols.home=${OLS_HOME} /opt/OLS/ols-web/target/ols-boot.war
