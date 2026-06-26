resource "docker_image" "prometheus" {
  name         = "prom/prometheus:latest"
  keep_locally = true
}

resource "docker_container" "prometheus" {
  name  = "prometheus"
  image = docker_image.prometheus.image_id

  restart = "unless-stopped"

  networks_advanced {
    name = data.docker_network.cicd.name
  }

  ports {
    internal = 9090
    external = 9090
  }

  mounts {
    target    = "/etc/prometheus/prometheus.yml"
    source    = abspath("${path.module}/../monitoring/prometheus.yml")
    type      = "bind"
    read_only = true
  }

  mounts {
    target    = "/etc/prometheus/alerts.yml"
    source    = abspath("${path.module}/../monitoring/alerts.yml")
    type      = "bind"
    read_only = true
  }

  command = [
    "--config.file=/etc/prometheus/prometheus.yml",
    "--storage.tsdb.retention.time=15d"
  ]
}

resource "docker_image" "grafana" {
  name         = "grafana/grafana:latest"
  keep_locally = true
}

resource "docker_container" "grafana" {
  name  = "grafana"
  image = docker_image.grafana.image_id

  restart = "unless-stopped"

  networks_advanced {
    name = data.docker_network.cicd.name
  }

  ports {
    internal = 3000
    external = 3000
  }

  env = [
    "GF_SECURITY_ADMIN_PASSWORD=admin"
  ]
}