vnc-server
==========

Ansible role that sets up a VNC server on CentOS 7.

Requirements
------------

Ansible version >= 2.3.

Role Variables
--------------

* user - user to start a VNC server
* password - default VNC password (by default `password`)
* display - display number (by default :2)

Dependencies
------------

None

Example Playbook
----------------

    - hosts: servers
      roles:
      - role: vncserver
        user: oracle 
        password: password
        display: :3
