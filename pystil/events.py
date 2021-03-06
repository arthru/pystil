
import pickle
import sys
import pika
import gevent
from gevent.event import Event

POLLS = {}
CACHE_SIZE = 20


class Poll(object):

    def __init__(self, site):
        self.event = Event()
        self.visits = []
        self._offset = 0

    def get(self, i):
        if i == len(self.visits) + self._offset:
            self.event.wait()
        i = max(i - self._offset, 0)
        return self.visits[i:], len(self.visits) + self._offset

    def add(self, visit):
        self.visits.append(visit)
        if len(self.visits) > CACHE_SIZE:
            self.visits.pop(0)
            self._offset += 1
        self.event.set()
        self.event.clear()


def get_poll(site):
    if not POLLS.get(site):
        POLLS[site] = Poll(site)
    return POLLS[site]


def init_events(app):
    connection = pika.BlockingConnection(
        pika.ConnectionParameters(host='localhost'))
    channel = connection.channel()
    channel.queue_declare(queue='pystil_push')

    def callback(ch, method, properties, body):
        app.logger.debug('Got a message')
        from pystil.data.utils import polish_visit
        try:
            visit = pickle.loads(body)
            site = visit['host']
            visit = polish_visit(visit)
            # Release site event
            poll = get_poll(site)
            poll.add(visit)
            # If there is a subdomain release the super domain
            parts = site.split('.')
            if len(parts) > 2:
                supersite = '.'.join([parts[-2], parts[-1]])
                superpoll = get_poll(supersite)
                superpoll.add(visit)
            # Release all event
            all = get_poll('all')
            all.add(visit)
            ch.basic_ack(delivery_tag=method.delivery_tag)
            app.logger.debug('Message acknowledged')
        except Exception:
            app.logger.exception('Push callback crashed')

    channel.basic_consume(callback, queue='pystil_push')
    app.logger.info('Spawning blocking consume')
    # Is it good or awful ?
    gevent.spawn(channel.start_consuming)
