#!/usr/bin/env python
# -*- coding: utf-8 -*-
# Copyright (C) 2011-2013 by Florian Mounier, Kozea
# This file is part of pystil, licensed under a 3-clause BSD license.

from tornado.ioloop import IOLoop
from tornado.options import options, parse_command_line, parse_config_file
from subprocess import call
import logging.config

import pystil
parse_command_line()
if options.conffile:
    parse_config_file(options.conffile)
if options.log_conffile:
    options.logging = None
    logging.config.fileConfig(options.log_conffile)


import pystil.routes
import pystil.charts
import pystil.websocket
from pystil.context import pystil

pystil.listen(options.port, address=options.address, xheaders=True)
if options.debug:
    try:
        call("wsreload --url 'http://l:1789/*'", shell=True)
    except:
        pass

IOLoop.instance().start()
