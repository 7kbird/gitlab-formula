{% import_yaml "gitlab/defaults.yaml" as defaults with context %}
{% from "gitlab/map.jinja" import get_environment with context %}

{% set images = [] %}

{% for docker_name in salt['pillar.get']('gitlab:dockers', {}) %}
{% set docker = salt['pillar.get']('gitlab:dockers:' ~ docker_name,
                                  default=defaults.docker, merge=True) %}
{% set links = [] %}
{% do links.append(docker.database.link ~ ':postgresql') if 'link' in docker.database %}
{% do links.append(docker.redis.link ~ ':redisio') if 'link' in docker.redis %}

{% set image = docker.image if ':' in docker.image else docker.image ~ ':latest' %}
{% do images.append(image) if image not in images %}
{% set no_ip_extern_dockers = [] %}

gitlab-docker-running_{{ docker_name }}:
  dockerng.running:
    - name: {{ docker_name }}
    - image: {{ image }}
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
    {% if docker.publish %}
    - port_bindings:
      {%   if docker.https %}
      - '{{ docker.get('port', '443') }}:{{ docker.docker_https_port }}'
      {%   else %}
      - '{{ docker.get('port', '80') }}:{{ docker.docker_http_port }}'
      {%   endif %}
      {% if 'ssh_port' in docker %}
      - '{{ docker.ssh_port }}:{{ docker.docker_ssh_port }}'
      {% endif %}
    {% endif %}
    - binds:
      - {{ docker.data_dir }}:{{ docker.docker_data_dir}}
      {% if 'repos_dir' in docker %}
      - {{ docker.repos_dir }}:{{ docker.docker_repos_dir }}
      {% endif %}
    {% if 'extra_hosts' in docker%}
    - extra_hosts:
      {% for ex_host in docker.extra_hosts.get('hosts', []) %}
      - {{ ex_host }}
      {% endfor %}
      {% for ex_host, ex_docker in docker.extra_hosts.get('dockers', {}).items() %}
        {% if ex_docker in salt['dockerng.list_containers']() %}
          {% set ex_docker_ip = salt['dockerng.inspect_container'](ex_docker).NetworkSettings.IPAddress %}
          {% if ex_docker_ip %}
      - '{{ ex_host }}:{{ ex_docker_ip }}'{% continue%}
          {% endif %}
        {% endif %}
        {% do no_ip_extern_dockers.append(ex_docker) %}
      {% endfor %}
    {% endif %}
    - require:
      - cmd: gitlab-docker-image_{{ image }}

{% if no_ip_extern_dockers %}
gitlab-docker-{{ docker_name }}-depends-dockers-not-started:
  test.fail_without_changes:
    - name: 'Gitlab depend dockers not started:[{{ no_ip_extern_dockers|join(',') }}]'
{% endif %}

{% if 'certs' in docker %}
  {% set certs = { 'gitlab.key':docker.certs.key,
                   'gitlab.crt':docker.certs.crt,
                   'dhparam.pem':docker.certs.dhparam} %}
  {% for cert_name, cert in certs.items() %}
gitlab-docker-{{ docker_name}}-certs_{{ cert_name }}:
  file.copy:
    - name: {{ cert.get('path', docker.data_dir ~ '/certs/' ~  cert_name) }}
    - source: {{ cert.source }}
    - makedirs: True
    - force: True
    - mode: 400   # read only
    - watch_in:
      - dockerng: {{ docker_name }}
  {% endfor %}
{% endif %}

{% endfor %}

{% for image in images%}
gitlab-docker-image_{{ image }}:
  cmd.run:
    - name: docker pull {{ image }}
    - unless: '[ $(docker images -q {{ image }}) ]'
{% endfor %}
