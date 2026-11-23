# Keycloak 26 + Drifpen User Storage SPI (import-off federation).
# Build context: repo root. Uses prebuilt JAR (no Maven pull on Railway).
FROM quay.io/keycloak/keycloak:26.0.7
COPY services/keycloak/providers/keycloak-drifpen-spi-1.0.0.jar /opt/keycloak/providers/keycloak-drifpen-spi.jar
COPY services/keycloak/entrypoint.sh /opt/keycloak/entrypoint.sh
USER root
RUN chmod +x /opt/keycloak/entrypoint.sh
USER keycloak
ENV KC_HEALTH_ENABLED=true \
    KC_HTTP_ENABLED=true \
    KC_HOSTNAME_STRICT=false \
    KC_PROXY_HEADERS=xforwarded
ENTRYPOINT ["/opt/keycloak/entrypoint.sh"]
