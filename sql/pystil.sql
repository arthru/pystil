--
-- PostgreSQL database dump
--


CREATE EXTENSION IF NOT EXISTS hstore;
create schema agg;

--
-- Name: create_aggregate_table(character varying, text[], hstore, text[]); Type: FUNCTION; Schema: public; Owner: pystil
--

CREATE FUNCTION create_aggregate_table(table_name character varying, attributes text[], columndefs hstore, pkeys text[]) RETURNS void
    LANGUAGE plpgsql
    AS $_$
	DECLARE 
		func_stmt text;
		where_clauses text[];
		group_by_clauses text[];
		attribute text;
		columndef text;
		preconds text[];
	BEGIN
		func_stmt = 'CREATE TABLE agg.' || table_name || ' as (' || $$
		  SELECT host,
		  date_trunc('day', date)::date as date,
		$$ ;
		FOREACH attribute in ARRAY attributes LOOP
		    columndef = coalesce(columndefs -> attribute, attribute);
			columndef = replace(columndef, 'NEW.', 'visit.');
			group_by_clauses = group_by_clauses || columndef;
			func_stmt = func_stmt || columndef || ' as ' || attribute || ',';
		END LOOP;
		func_stmt = func_stmt || $$ 
			count(1) as fact_count
			from visit
			where $$;
		FOREACH attribute in ARRAY pkeys LOOP
		    columndef = coalesce(columndefs -> attribute, 'NEW.' || attribute);
			preconds = preconds || (columndef || ' is not null');
			columndef = '( ' || replace(columndef, 'NEW.', 'visit.') || ' ) is not null' ;
			where_clauses = where_clauses || columndef;
		END LOOP;
		where_clauses = where_clauses || 'visit.host is not null'::text;
		preconds = preconds || 'NEW.host is not null'::text;
		func_stmt = func_stmt || array_to_string(where_clauses, ' and ');
		func_stmt = func_stmt || E' group by host, date_trunc(\'day\', date), ' || array_to_string(group_by_clauses, ', ');
		func_stmt = func_stmt || ') ;';
		EXECUTE func_stmt;
		func_stmt = 'ALTER TABLE agg.' || table_name || ' add primary key (date, host, ' || array_to_string(pkeys, ',') || ')';
		EXECUTE func_stmt;
		PERFORM agg.create_upsert_func(table_name, array_to_string(preconds, ' and ')::varchar, columndefs); 
	END;
$_$;


-- This function takes a tablename (existing in the agg schema, and a precondition, and creates a trigger named on the visit table
-- maintaining the aggregate table
create or replace function agg.create_upsert_func(tablename varchar, precond varchar, columndefs hstore) returns void as $create_upsert_func$
	DECLARE
		-- The function definition
		func_stmt text;
		-- A cursor for all columns in the table
		allcolumns text[];
		-- A cursor for primary key columns
		idcolumns text[];
		-- A 'buffer' for storing a columnname when iterating over one of the aboves cursor
		columnname text;
		columndef text;

		whereclauses text[];
	BEGIN	
	  	-- Fetch all columns
	    select array_agg(column_name::text) into allcolumns 
		from information_schema.columns
		where table_schema = 'agg' and table_name = tablename;

		select array_agg(column_name::text) into idcolumns
		from information_schema.columns
		where table_schema = 'agg' and table_name = tablename and column_name in 
			(SELECT kcu.column_name 
			  from information_schema.key_column_usage kcu 
			  where kcu.table_name = tablename 
			  and kcu.column_name = columns.column_name);
		
		-- Initial function declaration
		func_stmt = $func_def$ 
			create or replace function agg.upsert_$func_def$ || tablename || $func_def$ () returns TRIGGER as $func_body$
			BEGIN
			-- Set the search path to the agg schema to make it easier to reference tables.
			-- Wrap the whole logic in the supplied 'precondition'
			IF ($func_def$ || precond || $func_def$) THEN
			  UPDATE agg.$func_def$ || tablename || $func_def$ set fact_count = fact_count + 1
			  WHERE
		$func_def$;

		-- Building the update 'where' clause, iterating over idcolumns.
		FOREACH columnname in ARRAY idcolumns  LOOP
		  columndef = coalesce(columndefs -> columnname, 'NEW.' || columnname);
          IF (columnname = 'date'::text) THEN
            columndef = E'date_trunc(\'day\', NEW.date)';
          END IF;
		  whereclauses = whereclauses || ( columnname || '=' || columndef);
 		END LOOP;
		func_stmt = func_stmt || array_to_string(whereclauses, ' and ') || ';';

		-- If update matches nothing, build an insert clause
		func_stmt = func_stmt || $func_def$
			IF NOT FOUND THEN
			  INSERT INTO agg.$func_def$ || tablename || '(';
		func_stmt = func_stmt || array_to_string(allcolumns, ', ') || ') values (';
		whereclauses = array[]::text[];
		FOREACH columnname in ARRAY allcolumns LOOP
		  IF (columnname = 'fact_count') THEN
			columndef = '1';
		  ELSE 
		  	columndef = coalesce(columndefs -> columnname, 'NEW.' || columnname);
		  END IF;
		  whereclauses = whereclauses || columndef;
 		END LOOP;
		func_stmt = func_stmt || array_to_string(whereclauses, ' ,') || ' ) ;';
		func_stmt = func_stmt || $$
  			END IF;
			END IF;
			RETURN NULL;
		END $func_body$ language plpgsql;$$;
		
		-- Finally, execute the stmt
		IF (func_stmt is not null) THEN
			EXECUTE func_stmt;
		ELSE
		  RAISE EXCEPTION 'Something went bad, check the table name';
		END IF;
		-- EXECUTE 'drop trigger if exists agg_visit_' || tablename || ' ON public.visit;';
		EXECUTE 'create trigger agg_visit_' || tablename || $$ 
			AFTER INSERT ON VISIT FOR EACH ROW EXECUTE PROCEDURE agg.upsert_$$ || tablename || '();';

	END;
$create_upsert_func$ language plpgsql;

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


--
-- Name: visit_part_trig; Type: TRIGGER; Schema: public; Owner: pystil
--

--CREATE TRIGGER visit_part_trig BEFORE INSERT ON visit FOR EACH ROW EXECUTE PROCEDURE visit_part_trig_func();


select create_aggregate_table('by_domain', 
  ARRAY['domain', 'subdomain'], 
  hstore('domain',  $$(case 
  				WHEN split_part(NEW.host, '.', 3) = '' 
				  then NEW.host
  				ELSE substr(NEW.host, strpos(NEW.host, '.') + 1, length(NEW.host) - strpos(NEW.host, '.') + 1) 
  			 END)$$) ||
    hstore('subdomain', $$(case 
					WHEN split_part(NEW.host, '.', 3) != ''
					  THEN split_part(NEW.host, '.', 1)
  					 ELSE NULL END)$$),
	ARRAY['domain']);

select create_aggregate_table('by_browser', 
  ARRAY['browser_name', 'browser_version', 'browser_name_version'], 
  hstore('browser_name_version', $$(
	NEW.browser_name || ' ' || split_part(NEW.browser_version, '.', 1) || (CASE 
		WHEN NEW.browser_name in ('opera', 'safari', 'chrome') 
			THEN ''
	  	ELSE '.' || split_part(NEW.browser_version, '.', 2) 
		END))$$),
	ARRAY['browser_name', 'browser_version']);


select create_aggregate_table('by_ip', ARRAY['ip'], NULL, ARRAY['ip']);

select create_aggregate_table('by_geo', ARRAY['country_code', 'country', 'city'], NULL, ARRAY['country_code', 'country', 'city']);

select create_aggregate_table('by_platform', ARRAY['platform'], NULL, ARRAY['platform']);

select create_aggregate_table('by_referrer', ARRAY['referrer', 'pretty_referrer', 'referrer_domain'], NULL, ARRAY['referrer']);

select create_aggregate_table('by_size', ARRAY['size'], NULL, ARRAY['size']);

select create_aggregate_table('by_page', ARRAY['page'], NULL, ARRAY['page']);

select create_aggregate_table('by_hash', ARRAY['page', 'hash'], NULL, ARRAY['page', 'hash']);

select create_aggregate_table('by_hour', ARRAY['hour'], 
  hstore('hour',  $$
	date_part('hour', NEW.date)$$), 
  ARRAY['hour']);

select create_aggregate_table('by_uuid', ARRAY['uuid'], NULL, ARRAY['uuid']);

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
