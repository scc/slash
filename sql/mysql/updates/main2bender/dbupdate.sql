alter table users modify passwd varchar(32) not null;
alter table users add newpasswd varchar(32);
alter table vars modify column name varchar(32) NOT NULL DEFAULT '';
alter table vars modify column value text;
alter table vars modify column description varchar(127);
alter table vars add column datatype varchar(10);
alter table vars add column dataop varchar(12);

