
install_osg:
  pkg.installed:
    - sources:
      - osg-release: https://repo.opensciencegrid.org/osg/3.6/osg-3.6-el7-release-latest.rpm
    
osg_packages:
  pkg.installed:
    - pkgs:
      - autofs
      - osg-oasis
      - singularity
      - condor

/etc/cvmfs/default.local: 
  file.managed:
    - mode: 644
    - source: salt://osg/default.local

/etc/auto.master.d/cvmfs.autofs: 
  file.managed:
    - mode: 644
    - source: salt://osg/cvmfs.autofs

autofs:
  service.running:
    - enable: True
    - reload: True
    - watch:
      - file: /etc/auto.master.d/cvmfs.autofs

/usr/sbin/osgvo-node-advertise:
  file.managed:
    - mode: 755
    - source: salt://osg/osgvo-node-advertise

/usr/sbin/user-job-wrapper.sh:
  file.managed:
    - mode: 755
    - source: salt://osg/user-job-wrapper.sh

/usr/sbin/osgvo-check-shutdown:
  file.managed:
    - mode: 755
    - source: salt://osg/osgvo-check-shutdown

/etc/condor/config.d/10-osg.conf:
  file.managed:
    - mode: 644
    - source: salt://osg/10-osg.conf

condor:
  service.running:
    - enable: True
    - reload: True
    - watch:
      - file: /etc/condor/config.d/10-osg.conf


