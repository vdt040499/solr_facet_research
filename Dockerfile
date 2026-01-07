FROM solr:latest

# Metadata
LABEL maintainer="your-email@example.com"
LABEL description="Solr with Vietnamese tokenizer and wordcloud config"

# Copy Vietnamese tokenizer plugins (loại trừ commons-io để tránh conflict với bản trong Solr)
COPY lib/VnCoreNLP-1.1.1.jar \
     lib/activation-1.1.1.jar \
     lib/jaxb-api-2.3.0.jar \
     lib/jaxb-core-2.3.0.jar \
     lib/jaxb-impl-2.3.0.jar \
     lib/solr-vn-analyzer-1.0.jar \
     /opt/solr/server/lib/

# Copy configset
COPY wordcloud_config_test /opt/solr/server/solr/configsets/wordcloud_config

# Copy data file vào image
COPY exported_data_no_version.json /opt/solr/data/exported_data_no_version.json

# Copy entrypoint script
COPY docker-entrypoint.sh /opt/solr/docker-entrypoint.sh

# Set permissions
USER root
RUN chown -R solr:solr /opt/solr/server/lib/*.jar && \
    chown -R solr:solr /opt/solr/server/solr/configsets/wordcloud_config && \
    chown -R solr:solr /opt/solr/data && \
    chmod +x /opt/solr/docker-entrypoint.sh
USER solr

# Expose Solr port
EXPOSE 8983

# Sử dụng entrypoint script để tự động import data
ENTRYPOINT ["/opt/solr/docker-entrypoint.sh"]

