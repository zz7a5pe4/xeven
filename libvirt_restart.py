#!/usr/bin/python

import libvirt
import os

def main():
    l = open("vmsh/latest", "r")
    c = l.readline().strip()
    conn=libvirt.open("qemu:///system")
    statslist = os.listdir("vmsh")
    for s in statslist:
        if c in s:
            print "create {0}".format(s)
            f = open("vmsh/"+s, "r")
            xmldom = ""
            for line in f.readlines():
                xmldom += line
            conn.createXML(xmldom,0)
    l.close()

if __name__ == "__main__":
    main()
