#!/usr/bin/python

import os
import sys
import site

VENV_SITE_DIR = "/srv/venv/pystil/lib/python2.6/site-packages/"

site.addsitedir( VENV_SITE_DIR )

from os.path import dirname, abspath
path = dirname( abspath( __file__ ) )
if path not in sys.path:
    sys.path.append(path)

import werkzeug.contrib.fixers
from pystil import app, config

config.CONFIG["SECRETS_FILE"] = '/var/www/pystil/pystil.conf'
config.CONFIG["DEBUG"] = False
config.CONFIG["TESTING"] = False
## config.CONFIG["IP_DB"] = os.path.join(os.path.dirname(__file__), 'ip.db')
config.CONFIG["LOG_FILE"] = '/var/log/apache2/pystil/wsgi.log'
config.freeze()

from pystil.service.http import Application

application = werkzeug.contrib.fixers.ProxyFix(Application(app()))
