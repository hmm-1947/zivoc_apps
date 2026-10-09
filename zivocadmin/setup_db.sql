CREATE USER zivocappdbuser WITH PASSWORD 'joshuajosephzivoc';
CREATE DATABASE zivocappdb OWNER zivocappdbuser;
GRANT ALL PRIVILEGES ON DATABASE zivocappdb TO zivocappdbuser;
\c zivocappdb
ALTER SCHEMA public OWNER TO zivocappdbuser;
GRANT ALL ON SCHEMA public TO zivocappdbuser;
GRANT ALL ON ALL TABLES IN SCHEMA public TO zivocappdbuser;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO zivocappdbuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO zivocappdbuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO zivocappdbuser;
