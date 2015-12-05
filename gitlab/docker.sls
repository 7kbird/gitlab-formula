{% import_yaml "gitlab/defaults.yaml" as defaults with context %}
{% from "gitlab/map.jinja" import get_environment with context %}

{% for docker_name in salt['pillar.get']('gitlab:dockers', {}) %}
{% set docker = salt['pillar.get']('gitlab:dockers:' ~ docker_name,
                                  default=defaults.docker, merge=True) %}
{% set links = [] %}
{% do links.append(docker.database.link ~ ':postgresql') if 'link' in docker.database %}
{% do links.append(docker.redis.link ~ ':redisio') if 'link' in docker.redis %}

gitlab-docker-running_{{ docker_name }}:
  dockerng.running:
    - name: {{ docker_name }}
    - image: {{ docker.image }}
    - ports:
      - {{ docker.docker_http_port }}
      - {{ docker.docker_https_port }}
      - {{ docker.docker_ssh_port }}
    - links:
      {% for link in links %}
      - {{ link }}
      {% endfor %}
    - environment:
      {{ get_environment(docker)|indent(6)}}
    - port_bindings:
    {% if 'port' in docker %}
    {%   if docker.https %}
      - '{{ docker.port }}:{{ docker.docker_https_port }}'
    {%   else %}
      - '{{ docker.port }}:{{ docker.docker_http_port }}'
    {%   endif %}
    {% endif %}
    {% if 'ssh_port' in docker %}
      - '{{ docker.ssh_port }}:{{ docker.docker_ssh_port }}'
    {% endif %}
    - binds: {{ docker.data_dir }}:{{ docker.docker_data_dir}}
{% endfor %}
