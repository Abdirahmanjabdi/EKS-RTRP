FROM grafana/grafana:13.1.2

COPY provisioning/datasources/prometheus.yml /etc/grafana/provisioning/datasources/prometheus.yml
COPY provisioning/dashboards/dashboard.yml /etc/grafana/provisioning/dashboards/dashboard.yml
COPY dashboards/ /etc/grafana/provisioning/dashboards/definitions/
