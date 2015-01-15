======
Pystil
======

Pystil is an elegant site web traffic analyzer written in python and coffeescript

Quickstart
==========

Requirements :

 - python 3
 - PostgreSQL server, with hstore and ip4r extensions

.. code-block:: sh

  git clone https://github.com/Kozea/pystil.git
  cd pystil
  pip install -r requirements.txt
  createdb pystil
  cat sql/pystil.sql | psql pystil
  cd sql/geoip && ./sync-db.bash && cat import.sql | psql pystil && cd ../..
  python -m pystil


Options
=======

--db_host
  Pystil db host (default localhost)

--db_name
  Pystil db name (default pystil)

--db_password
  Pystil db password (default pystil)

--db_port
  Pystil db port (default 5432)

--db_user
  Pystil db user (default pystil)

--debug
  Debug mode (default False)

--help
  show this help information

--address
  Pystil address to answer on

--port
  Pystil port (default 1789)

--protocol
  Protocol if behind proxy (default http)

--secret
  Cookie secret (default REPLACE_ME)

--log_conffile
  Path to an INI log configuration file (see the `configuration fileformat doc <https://docs.python.org/3.4/library/logging.config.html#logging-config-fileformat>`_ ; default None)
