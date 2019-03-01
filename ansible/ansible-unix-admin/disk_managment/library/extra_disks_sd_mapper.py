#!/usr/bin/env python
from ansible.module_utils.basic import AnsibleModule
import os
import subprocess
import copy

DOCUMENTATION = '''
---
module: extra_disks_sd_mapper
short_description: map extra-disks to sd devices
description:
  - reorders extra VMDKs and assign to avaiable sd devices as needed
version: 1.0
author:
  - "Anitesh A. Lal"
options:
  field:
    description:
      - the field to sort on (supported: mount_point)
    required: False
  order:
    description:
      - the orser to sort with (supported: alphanumeric)
    required: False
  edisks:
    description:
      - a list of dicts containing size, fstype, mount_point
    required: True
  devices:
    description:
      - ansible_devices from gathering facts
    required: True
  mounts:
    description:
      - ansible_mounts from gathering facts
    required: True
'''

EXAMPLES = '''
- name: map extra-disks to sd devices
  extra_disks_sd_mapper:
    field: mount_point
    order: alphanumeric
    edisks: "{{ extra-disks }}"
    devices: "{{ ansible_devices }}"
    mounts: "{{ ansible_mounts }}"
'''

RETURN = '''
extra-disks-map:
    description: list of dictionaries describing the extra-disks mapped to sd devices in a alphanumeric order
    returned: success
    type: list
    sample:
    - { dev: 'sde', size:  '1.00 GB', fstype: 'xfs', mount_point: '/opt/home/svc-saprouter' }
    - { dev: 'sdd', size:  '1.00 GB', fstype: 'xfs', mount_point: '/opt/home/ws1adm' }
    - { dev: 'sdb', size: '10.00 GB', fstype: 'xfs', mount_point: '/usr/sap' }
    - { dev: 'sdc', size: '25.00 GB', fstype: 'xfs', mount_point: '/usr/sap/WS1' }
'''

def get_uuid_for_mount_point(m,mount_point):
  """
  get UUID for a given mount point otherwise return None

  >>> m = { 'cf91c6f2-3e1b-48f4-b7fd-adb17aac541b': { 'device': '/dev/sdc1', 'fstype': 'xfs', 'mount': '/test/mnt', 'uuid': 'cf91c6f2-3e1b-48f4-b7fd-adb17aac541b' } }
  >>> get_uuid_for_mount_point(m,'/fake/mnt')

  >>> get_uuid_for_mount_point(m,'/test/mnt')
  'cf91c6f2-3e1b-48f4-b7fd-adb17aac541b'
  """
  retval=None
  for uuid, mnt in m.items():
    if mnt['mount'] == mount_point:
      retval=uuid

  return retval

def get_mount_point_attrs(edisk,d,m):
  """
  get the device and UUID if available for a given edisk
  Note:
  o  if device is returned as None then there is no available match
  o  if UUID is returned as None then the given device needs to be initialized
  o  if size is returned as None this indicated a size mismatch
  o  if fstype is returned as None this indicated a fstype mismatch

  >>> edisk1 = { 'size': '10.00 GB', 'fstype': 'xfs', 'mount_point': '/test/mnt' }
  >>> d = { 'sdc': {'partitions': { 'sdc1': { 'size': '10.00 GB', 'uuid': 'cf91c6f2-3e1b-48f4-b7fd-adb17aac541b'} }, 'size': '10.00 GB' } }
  >>> m = { 'cf91c6f2-3e1b-48f4-b7fd-adb17aac541b': { 'device': '/dev/sdc1', 'fstype': 'xfs', 'mount': '/test/mnt', 'uuid': 'cf91c6f2-3e1b-48f4-b7fd-adb17aac541b' } }
  >>> sorted(get_mount_point_attrs(edisk1,d,m).items())
  [('dev', 'sdc'), ('fstype', 'xfs'), ('mount_point', '/test/mnt'), ('size', '10.00 GB'), ('uuid', 'cf91c6f2-3e1b-48f4-b7fd-adb17aac541b')]

  >>> edisk2 = { 'size': '50.00 GB', 'fstype': 'xfs', 'mount_point': '/no-dev-match/mnt' }
  >>> sorted(get_mount_point_attrs(edisk2,d,m).items())
  [('dev', None), ('fstype', 'xfs'), ('mount_point', '/no-dev-match/mnt'), ('size', '50.00 GB'), ('uuid', None)]

  >>> edisk3 = { 'size': '10.00 GB', 'fstype': 'xfs', 'mount_point': '/new/mnt' }
  >>> d = { 'sdc': { 'partitions': {}, 'size': '10.00 GB' } }
  >>> m = {}
  >>> sorted(get_mount_point_attrs(edisk3,d,m).items())
  [('dev', 'sdc'), ('fstype', 'xfs'), ('mount_point', '/new/mnt'), ('size', '10.00 GB'), ('uuid', None)]

  >>> d = {}
  >>> m = { 'cf91c6f2-3e1b-48f4-b7fd-adb17aac541b': { 'device': '/dev/sdc1', 'fstype': 'xfs', 'mount': '/test/mnt', 'uuid': 'cf91c6f2-3e1b-48f4-b7fd-adb17aac541b' } }
  >>> sorted(get_mount_point_attrs(edisk1,d,m).items())
  Traceback (most recent call last):
  ...
  ReferenceError: uuid cf91c6f2-3e1b-48f4-b7fd-adb17aac541b exists in mount but not in device list
  """
  edisk['uuid'] = get_uuid_for_mount_point(m,edisk['mount_point'])
  edisk['dev'] = None

  if edisk['uuid'] == None:
    for dev in sorted(d.keys()):
      if len(d[dev]['partitions']) == 0 and d[dev]['size'] == edisk['size']:
          edisk['dev'] = dev
          break # assign the first dev to this edisk
  else:
    for dev in sorted(d.keys()):
      for part in sorted(d[dev]['partitions'].keys()):
        if d[dev]['partitions'][part]['uuid'] == edisk['uuid']:
          edisk['dev'] = dev

          # note: partition sizes my be slightly smaller so use dev size instead :)
          if d[dev]['size'] != edisk['size']:
            edisk['size'] = None

          if m[edisk['uuid']]['fstype'] != edisk['fstype']:
            edisk['fstype'] = None

    if edisk['dev'] == None:
      raise ReferenceError("uuid {0} exists in mount but not in device list".format(edisk['uuid']))

  return edisk

def unmounted_uuid_exists(d,m):
  """
  return a boolean value of the state if any UUIDs exists that are not mounted
  If they do then to avoid possibly recreating the same ones fail if devices
  need to be initialized

  >>> d = { 'sdc': {'partitions': { 'sdc1': { 'size': '10.00 GB', 'uuid': 'cf91c6f2-3e1b-48f4-b7fd-adb17aac541b'} }, 'size': '10.00 GB' } }
  >>> m = {}
  >>> unmounted_uuid_exists(d,m)
  True

  >>> m = { 'cf91c6f2-3e1b-48f4-b7fd-adb17aac541b': { 'device': '/dev/sdc1', 'fstype': 'xfs', 'mount': '/test/mnt', 'uuid': 'cf91c6f2-3e1b-48f4-b7fd-adb17aac541b' } }
  >>> unmounted_uuid_exists(d,m)
  False
  """
  retval = False
  for dev in d:
    if 'partitions' in d[dev]:
      partitions = d[dev]['partitions']
      for attrs in partitions.values():
        if attrs['uuid'] not in m:
          retval = True

  return retval

def remap_mount(m):
  """
  remap the mount point list of dicts to a dict of dicts with a uuid key

  >>> m = [ { 'device': '/dev/sdc1', 'fstype': 'xfs', 'mount': '/test/mnt', 'uuid': 'cf91c6f2-3e1b-48f4-b7fd-adb17aac541b' } ]
  >>> remap_mount(m) # doctest: +ELLIPSIS
  {'cf91c6f2-3e1b-48f4-b7fd-adb17aac541b': {...}}

  >>> m = [ { 'uuid': 'cf91c6f2-3e1b-48f4-b7fd-adb17aac541b' }, { 'uuid': '260be711-22db-4562-bb22-9da41c741412' }, { 'uuid': '89a5a5b4-35ac-40c2-9ba3-0f80ba05eaa7' } ]
  >>> sorted(remap_mount(m))
  ['260be711-22db-4562-bb22-9da41c741412', '89a5a5b4-35ac-40c2-9ba3-0f80ba05eaa7', 'cf91c6f2-3e1b-48f4-b7fd-adb17aac541b']
  """
  remap_m = dict()
  for mnt in m:
    remap_m[mnt['uuid']] = mnt

  return remap_m

def filter_sd(d):
  """
  get all devices starting with sd except sda

  >>> d = {}
  >>> sorted(filter_sd(d))
  []

  >>> d = { 'sda': {}, 'sdc': {}, 'sdb': {} }
  >>> sorted(filter_sd(d))
  ['sdb', 'sdc']

  >>> d = { 'sdaa': {}, 'sda': {}, 'sdc': {}, 'sdb': {} }
  >>> sorted(filter_sd(d))
  ['sdaa', 'sdb', 'sdc']
  """
  remap_d = dict()
  for key, dev in d.items():
    if key[:2] == 'sd' and key[2:] != 'a':
      remap_d[key] = dev

  return remap_d

def reorder_edisks(module):
  """
  reorder extra disks list into a list based on alphanumeric by mount points

  # aniteshl: need a real test here [{...}]
  # from ansible.module_utils.basic import AnsibleModule
  # module = AnsibleModule(argument_spec=fields)
  # o  need to test each failure case as well as a successful case or two

  >>> import json
  >>> class Module(object):
  ...   def __init__(self, params):
  ...     self.params = params
  ...   def fail_json(self,msg,meta):
  ...     raise RuntimeError( json.dumps(meta) + ", " + json.dumps(msg))
  >>> edisk =  { 'dev': 'sdc', 'size': '10.00 GB', 'fstype': 'xfs', 'mount_point': '/test/mnt' }
  >>> d = { 'sdc': {'partitions': { 'sdc1': { 'size': '10.00 GB', 'uuid': 'cf91c6f2-3e1b-48f4-b7fd-adb17aac541b'} }, 'size': '10.00 GB' } }
  >>> m = [ { 'device': '/dev/sdc1', 'fstype': 'xfs', 'mount': '/test/mnt', 'uuid': 'cf91c6f2-3e1b-48f4-b7fd-adb17aac541b' } ]
  >>> module = Module( { 'edisks': {}, 'devices': d, 'mounts': m } )
  >>> reorder_edisks(module) # doctest: +ELLIPSIS
  []
  """
  try:
    e = module.params['edisks']
  except TypeError:
    module.fail_json(msg="failed to provide edisks attribute", meta={ 'module': module })

  try:
    d = module.params['devices']
  except TypeError:
    module.fail_json(msg="failed to provide devices attribute", meta={ 'module': module })

  try:
    m = module.params['mounts']
  except TypeError:
    module.fail_json(msg="failed to provide mounts attribute", meta={ 'module': module })

  # sort into a list based on alphanumeric order by mount points
  reorder_e = sorted(e, key=lambda k: k['mount_point'])

  # filter out devices that start with sd except sda
  filter_d = filter_sd(d)

  # remap mount points into a dict with a key of uuid
  remap_m = remap_mount(m)

  for i in range(len(reorder_e)):
    edisk = reorder_e[i]
    mydisk = copy.deepcopy(edisk)
    newdisk = get_mount_point_attrs(mydisk,filter_d,remap_m)

    # o  if size is returned as None this indicated a size mismatch
    if newdisk['size'] == None:
        module.fail_json(msg="size mismatch on edisk", meta={ 'edisk': edisk, 'newdisk': newdisk, 'e': e, 'devices': filter_d, 'mounts': remap_m })

    # o  if fstype is returned as None this indicated a fstype mismatch
    if newdisk['fstype'] == None:
      module.fail_json(msg="fstype mismatch on edisk", meta={ 'edisk': edisk, 'devices': filter_d, 'mounts': remap_m })

    # o  if UUID is returned as None then the given device needs to be initialized
    if newdisk['uuid'] == None:
      if unmounted_uuid_exists(filter_d,remap_m):
        module.fail_json(msg="unmounted partition identified with UUID", meta={ 'devices': filter_d, 'mounts': remap_m })
    else:
      reorder_e[i]['uuid'] = newdisk['uuid']

    # o  if device is returned as None then there is no available match
    if newdisk['dev'] == None:
        module.fail_json(msg="unable to find an available device for newdisk", meta={ 'newdisk': newdisk, 'devices': filter_d, 'mounts': remap_m })
    else:
      reorder_e[i]['dev'] = newdisk['dev']
      filter_d.pop(newdisk['dev']) # remove device from devices to avoid redundant allocations of it

  return reorder_e

def main():

  fields = {
    "field": {
      "default": "mount_point",
      "choices": [ 'mount_point' ],
      "type": 'str'
    },

    "order": {
      "default": "alphanumeric",
      "choices": [ 'alphanumeric' ],
      "type": 'str'
    },

    "edisks": { "type": 'list' },
    "devices": { "type": 'dict' },
    "mounts": { "type": 'list' },
  }

  module = AnsibleModule(argument_spec=fields)

  field_choice_map = {
    "mount_point": reorder_edisks(module),
  }

  extras = field_choice_map.get(module.params['field'])

  module.exit_json(changed=False, meta={ 'map': extras })

if __name__ == '__main__':
  main()
