connect slash;
INSERT INTO comments_hash SELECT * FROM comments;

#DROP TABLE IF EXISTS stories_hash;
#CREATE TABLE stories_hash (
#  sid char(16) DEFAULT '' NOT NULL,
#  tid varchar(20) DEFAULT '' NOT NULL,
#  uid int(11) DEFAULT '1' NOT NULL,
#  commentcount int(1) DEFAULT '0',
#  title varchar(100) DEFAULT '' NOT NULL,
#  dept varchar(100),
#  time datetime DEFAULT '0000-00-00 00:00:00' NOT NULL,
#  writestatus int(1) DEFAULT '0' NOT NULL,
#  hits int(1) DEFAULT '0' NOT NULL,
#  section varchar(30) DEFAULT '' NOT NULL,
#  displaystatus int(1) DEFAULT '0' NOT NULL,
#  commentstatus int(1),
#  hitparade varchar(64) DEFAULT '0,0,0,0,0,0,0',
#  PRIMARY KEY (sid),
#  KEY time (time),
#  KEY searchform (displaystatus,time)
#) TYPE=heap;
#INSERT INTO stories_hash SELECT * FROM stories;
