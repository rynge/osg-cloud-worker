#!/bin/bash

yum install -y https://repo.saltstack.com/py3/redhat/salt-py3-repo-3002.el7.noarch.rpm
yum install -y salt-minion

cp salt/salt/10-osg-worker.conf /etc/salt/minion.d/

salt-call state.highstate


