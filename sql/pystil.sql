--
-- PostgreSQL database dump
--


CREATE EXTENSION IF NOT EXISTS hstore;

--
-- Name: create_criterion_view(); Type: FUNCTION; Schema: public; Owner: pystil
--

CREATE FUNCTION create_criterion_view() RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
    first boolean;
    stmt text;
    s text;
begin
    stmt = 'create or replace view criterion_view as (';
    first = true;
    for s in select '(select * from ' || c.relname || ' order by date desc)'
        from pg_inherits
             join pg_class as c on (inhrelid=c.oid)
             join pg_class as p on (inhparent=p.oid)
        where p.relname = 'visit'
        order by c.relname desc
    loop
        if first then
            stmt = stmt || s;
            first = false;
        else
            stmt = stmt || ' union all ' || s;
        end if;
    end loop;
    stmt = stmt || ');';
    execute stmt;
end;
$$;


--
-- Name: geoip_bigint_to_str(bigint); Type: FUNCTION; Schema: public; Owner: pystil
--

CREATE FUNCTION geoip_bigint_to_str(p_ip bigint) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
    SELECT (($1 >> 24 & 255) || '.' || ($1 >> 16 & 255) || '.' || ($1 >> 8 & 255) || '.' || ($1 & 255))
$_$;


--
-- Name: int2interval(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION int2interval(x integer) RETURNS interval
    LANGUAGE sql
    AS $_$ select $1*'1 sec'::interval $_$;


--
-- Name: visit_part_trig_func(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION visit_part_trig_func() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$ 
        DECLARE
            v_count                 int;
            v_partition_name        text;
            v_partition_timestamp   timestamptz;
            v_schemaname            text;
            v_tablename             text;
        BEGIN 
        IF TG_OP = 'INSERT' THEN 
            v_partition_timestamp := date_trunc('month', NEW.date);
            v_partition_name := 'public.visit_p'|| to_char(v_partition_timestamp, 'YYYY_MM');
            v_schemaname := split_part(v_partition_name, '.', 1); 
            v_tablename := split_part(v_partition_name, '.', 2);
            SELECT count(*) INTO v_count FROM pg_tables WHERE schemaname = v_schemaname AND tablename = v_tablename;
            IF v_count = 0 THEN 
                EXECUTE 'SELECT create_partition(date ''' || to_char(NEW.date, 'YYYY-MM-DD') || ''')';
                EXECUTE 'SELECT create_criterion_view();';
            END IF;
            EXECUTE 'INSERT INTO '||v_partition_name||' VALUES($1.*)' USING NEW;
        END IF;
        
        RETURN NULL; 
        END $_$;


--
-- Name: CAST (integer AS interval); Type: CAST; Schema: pg_catalog; Owner: 
--

CREATE CAST (integer AS interval) WITH FUNCTION public.int2interval(integer) AS IMPLICIT;


--
-- Name: visit; Type: TABLE; Schema: public; Owner: pystil; Tablespace: 
--

CREATE TABLE visit (
    browser_name character varying,
    browser_version character varying,
    date timestamp without time zone NOT NULL,
    hash character varying,
    host character varying,
    ip character varying,
    language character varying,
    last_visit timestamp without time zone,
    page character varying,
    platform character varying,
    query character varying,
    referrer character varying,
    site character varying,
    size character varying,
    uuid character varying NOT NULL,
    client_tz_offset integer,
    country character varying,
    city character varying,
    lat numeric,
    lng numeric,
    id integer NOT NULL,
    country_code character varying,
    pretty_referrer character varying,
    "time" interval,
    referrer_domain character varying,
    asn character varying,
    day date,
    hour integer,
    subdomain character varying,
    domain character varying,
    browser_name_version character varying
);


--
-- Name: visit_id_seq; Type: SEQUENCE; Schema: public; Owner: pystil
--

CREATE SEQUENCE visit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: visit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: pystil
--

ALTER SEQUENCE visit_id_seq OWNED BY visit.id;


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: pystil
--

ALTER TABLE ONLY visit ALTER COLUMN id SET DEFAULT nextval('visit_id_seq'::regclass);


--
-- Name: pk; Type: CONSTRAINT; Schema: public; Owner: pystil; Tablespace: 
--

ALTER TABLE ONLY visit
    ADD CONSTRAINT pk PRIMARY KEY (id);


CREATE OR REPLACE FUNCTION create_partition(d date) RETURNS void
    LANGUAGE plpgsql
    AS $create_partition$
DECLARE
    start_ts timestamptz;
    end_ts timestamptz;
    partition text;
BEGIN
    start_ts := date_trunc('month', d);
    end_ts := date_trunc('month', d + interval '1 month');
    partition := to_char(start_ts, 'YYYY_MM');
    EXECUTE 'CREATE TABLE visit_p' || partition || ' ( CHECK ('
        || '(date >= ''' || to_char(start_ts, 'YYYY-MM-DD') || ' 00:00:00''::timestamp without time zone) AND '
        || '(date < ''' || to_char(end_ts, 'YYYY-MM-DD') || ' 00:00:00''::timestamp without time zone))) INHERITS (visit)';
    EXECUTE 'ALTER TABLE ONLY visit_p' || partition || ' ADD CONSTRAINT visit_p' || partition || '_pkey PRIMARY KEY (id)';
    EXECUTE 'CREATE INDEX visit_p' || partition || '_date_idx ON visit_p' || partition || ' USING btree (date)';
    EXECUTE 'CREATE INDEX visit_p' || partition || '_host_date_idx ON visit_p' || partition || ' USING btree (host, date)';

    EXECUTE 'CREATE INDEX visit_p' || partition || '_referrer_domain_idx ON visit_p' || partition || ' USING btree (referrer_domain)';

    EXECUTE 'CREATE INDEX visit_p' || partition || '_uuid_date_idx ON visit_p' || partition || ' USING btree (uuid, date DESC)';
    EXECUTE 'CREATE TRIGGER visit_part_trig_p' || partition || ' BEFORE INSERT ON visit_p' || partition || ' FOR EACH ROW EXECUTE PROCEDURE visit_part_trig_func();';

END;
$create_partition$;

SELECT create_partition(current_date);

--
-- Name: criterion_view; Type: VIEW; Schema: public; Owner: pystil
--

SELECT create_criterion_view();
