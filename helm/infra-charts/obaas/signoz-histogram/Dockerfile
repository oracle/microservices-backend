FROM alpine:3.24
RUN apk add --no-cache tar
ENV HISTOGRAM_QUANTILE_VERSION=v0.0.1
RUN mkdir -p /usr/local/bin/histogram-quantile
RUN mkdir -p /usr/local/bin/histogram-quantile \
 && wget -O /tmp/amd64.tar.gz \
    "https://github.com/SigNoz/signoz/releases/download/histogram-quantile%2F${HISTOGRAM_QUANTILE_VERSION}/histogram-quantile_linux_amd64.tar.gz" \
 && wget -O /tmp/arm64.tar.gz \
    "https://github.com/SigNoz/signoz/releases/download/histogram-quantile%2F${HISTOGRAM_QUANTILE_VERSION}/histogram-quantile_linux_arm64.tar.gz" \
 && tar -xzf /tmp/amd64.tar.gz -C /tmp \
 && mv /tmp/histogram-quantile \
    /usr/local/bin/histogram-quantile/histogram-quantile_linux_amd64 \
 && tar -xzf /tmp/arm64.tar.gz -C /tmp \
 && mv /tmp/histogram-quantile \
    /usr/local/bin/histogram-quantile/histogram-quantile_linux_arm64 \
 && chmod +x /usr/local/bin/histogram-quantile/* \
 && rm -rf /tmp/*
