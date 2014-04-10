# -*- coding: utf-8 -*-
# _returners/zeromq_return.py

'''
The zeromq returner will send return data back to the Salt Master over the
Encrypted 0MQ event bus with a custom tag for filtering on the other end. 

Basically after the remote execution finishes, the ret data is "packaged" into
a special "envelope" which triggers the local Salt Minion Daemon to
forward the ret data to the Salt Master's event bus. 

The "package" basically wraps the ret data and uses the tag 'fire_master'.

For example, a ret data object from the execution of test.ping
would be "packaged" like this::

  ret = {
    'graphite.foxhop.net': true
  }

  ret['tag'] = 'third-party'

  package = {
    'events': [ ret ],
    'tag': None,
    'pretag': None,
    'data': None
  }

The Salt Minion Daemon will forward this package to the Salt Master
where a 3rd party script may be filtering on the specified internal event tag.

To use the zeromq returner, append '--return zeromq' to the salt command. ex::

  salt --return zeromq '*' test.ping 

TODO:

 figure out a way for user to define custom tag for filtering ... 
 Most returners use the Salt Minion config file to supply returner
 details... that is not optimal, it would be ideal if the custom tag
 could be supplied on the CLI when the remote execution is run, like::

   --return=zeromq --tag=mytag

'''

# needed to log to log file
import logging

# needed for config to opts processing
import os
import salt.syspaths as syspaths
from salt.config import minion_config
# we want a uniq id for each event so we can put them into a DB without worry
import uuid 

# needed to send events over ZMQ
import salt.utils.event

log = logging.getLogger(__name__)

# needed to define the module's virtual name
__virtualname__ = 'zeromq'

def __virtual__():
    return __virtualname__


def returner(ret):
    '''
    Send the return data to the Salt Master over the encrypted
    0MQ bus with custom tag for 3rd party script filtering.
    '''

    # get opts from minion config file, supports minion.d drop dir!
    opts = minion_config(os.path.join(syspaths.CONFIG_DIR, 'minion'))

    # TODO: this needs to be customizable!
    tag = 'third-party'

    # add custom tag to return data for filtering
    ret['tag'] = tag

    # multi event example, supports a list of event ret objects.
    # single event does not currently expand/filter properly on Master side.
    package = {
      #'id': opts['id'],
      'events': [ ret ],
      'tag': None,
      'pretag': None,
      'data': None
    }

    # opts must contain valid minion ID else it binds to invalid 0MQ socket.
    event = salt.utils.event.SaltEvent('minion', **opts)

    # Fire event payload with 'fire_master' tag which triggers the
    # salt-minion daemon to forward payload to the master event bus!
    event.fire_event(package, 'fire_master')