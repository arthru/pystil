#!/usr/bin/env python2

import os
import sys
current_dir = os.path.dirname( os.path.abspath( __file__ ) )
pystil_parent_path = os.path.abspath( current_dir + "/.." )
if pystil_parent_path not in sys.path:
    sys.path.append( pystil_parent_path)

import pika
import pickle
from pystil import config

if __name__ == '__main__':
    # sys.stdout = open(os.devnull, "w")
    # sys.stderr = open("/var/log/pystil.err", "w")

    config.freeze()
    connection = pika.BlockingConnection(
        pika.ConnectionParameters(host='localhost'))
    channel = connection.channel()
    channel.queue_declare(queue='pystil')
    channel_out = connection.channel()
    channel_out.queue_declare(queue='pystil_push')

    def callback(ch, method, properties, body):
        message = pickle.loads(body)
        visit = message.process()
        if visit:
            channel_out.basic_publish(
                exchange='', routing_key='pystil_push',
                body=pickle.dumps(visit))
        ch.basic_ack(delivery_tag=method.delivery_tag)

    channel.basic_consume(callback, queue='pystil')
    channel.start_consuming()
