
/etc/salt/minion.d/10-osg-worker.conf:
  file.managed:
    - source: salt://salt/10-osg-worker.conf
    - user: root
    - group: root
    - mode: 644
    - template: jinja

salt-minion:
  service.running:
    - enable: True
    - watch:
      - file: /etc/salt/minion.d/10-osg-worker.conf

/etc/cron.d/salt:
  file.managed:
    - source: salt://salt/salt.cron
    - user: root
    - group: root
    - mode: 644
    - template: jinja

