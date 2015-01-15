======
Pystil
======

Pystil is an elegant site web traffic analyzer written in python and coffeescript

Quickstart
==========

Requirements :
- python 3
- PostgreSQL server, with hstore and ip4r extensions

  git clone https://github.com/Kozea/pystil.git
  cd pystil
  pip install -r requirements.txt
  createdb pystil
  cat sql/pystil.sql | psql pystil
  cd sql/geoip && ./sync-db.bash && cat import.sql | psql pystil && cd ../..
  python pystil2.py
