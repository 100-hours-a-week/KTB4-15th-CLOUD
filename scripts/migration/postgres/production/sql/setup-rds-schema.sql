-- V1 Prod의 실제 애플리케이션 구조를 V2 Prod RDS에 준비한다.
-- 데이터와 V1의 products_backup_* 테이블은 포함하지 않는다.

CREATE SCHEMA IF NOT EXISTS langgraph;

CREATE TABLE langgraph.checkpoint_blobs (
    thread_id text NOT NULL,
    checkpoint_ns text DEFAULT ''::text NOT NULL,
    channel text NOT NULL,
    version text NOT NULL,
    type text NOT NULL,
    blob bytea
);

CREATE TABLE langgraph.checkpoint_migrations (
    v integer NOT NULL
);

CREATE TABLE langgraph.checkpoint_writes (
    thread_id text NOT NULL,
    checkpoint_ns text DEFAULT ''::text NOT NULL,
    checkpoint_id text NOT NULL,
    task_id text NOT NULL,
    idx integer NOT NULL,
    channel text NOT NULL,
    type text,
    blob bytea NOT NULL,
    task_path text DEFAULT ''::text NOT NULL
);

CREATE TABLE langgraph.checkpoints (
    thread_id text NOT NULL,
    checkpoint_ns text DEFAULT ''::text NOT NULL,
    checkpoint_id text NOT NULL,
    parent_checkpoint_id text,
    type text,
    checkpoint jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE public.products (
    id bigint NOT NULL,
    product_code bigint NOT NULL,
    product_name text NOT NULL,
    price integer NOT NULL,
    color character varying(50) NOT NULL,
    detail_url text NOT NULL,
    image_url text NOT NULL,
    main_category character varying(20) NOT NULL,
    sub_category character varying(100) NOT NULL,
    is_sold_out boolean NOT NULL,
    crawled_at timestamp with time zone NOT NULL,
    image_attribute_keywords text[] NOT NULL,
    colors text[] NOT NULL,
    image_description text NOT NULL,
    description_summary text NOT NULL,
    embedding public.vector(1536) NOT NULL,
    has_been_recommended boolean DEFAULT false NOT NULL,
    CONSTRAINT products_price_check CHECK (price >= 0)
);

CREATE SEQUENCE public.products_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.products_id_seq OWNED BY public.products.id;

CREATE TABLE public.usage_amount (
    usage_date date NOT NULL,
    amount numeric DEFAULT 0 NOT NULL,
    reconciled_at timestamp with time zone
);

CREATE TABLE public.migration_test_events (
    event_id text NOT NULL,
    run_id text NOT NULL,
    client_id integer NOT NULL,
    event_no bigint NOT NULL,
    payload jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);

ALTER TABLE ONLY public.products
    ALTER COLUMN id SET DEFAULT nextval('public.products_id_seq'::regclass);

ALTER TABLE ONLY langgraph.checkpoint_blobs
    ADD CONSTRAINT checkpoint_blobs_pkey
    PRIMARY KEY (thread_id, checkpoint_ns, channel, version);

ALTER TABLE ONLY langgraph.checkpoint_migrations
    ADD CONSTRAINT checkpoint_migrations_pkey PRIMARY KEY (v);

ALTER TABLE ONLY langgraph.checkpoint_writes
    ADD CONSTRAINT checkpoint_writes_pkey
    PRIMARY KEY (thread_id, checkpoint_ns, checkpoint_id, task_id, idx);

ALTER TABLE ONLY langgraph.checkpoints
    ADD CONSTRAINT checkpoints_pkey
    PRIMARY KEY (thread_id, checkpoint_ns, checkpoint_id);

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_product_code_key UNIQUE (product_code);

ALTER TABLE ONLY public.usage_amount
    ADD CONSTRAINT usage_amount_pkey PRIMARY KEY (usage_date);

ALTER TABLE ONLY public.migration_test_events
    ADD CONSTRAINT migration_test_events_pkey PRIMARY KEY (event_id);

ALTER TABLE ONLY public.migration_test_events
    ADD CONSTRAINT migration_test_events_run_id_client_id_event_no_key
    UNIQUE (run_id, client_id, event_no);

CREATE INDEX checkpoint_blobs_thread_id_idx
    ON langgraph.checkpoint_blobs USING btree (thread_id);

CREATE INDEX checkpoint_writes_thread_id_idx
    ON langgraph.checkpoint_writes USING btree (thread_id);

CREATE INDEX checkpoints_thread_id_idx
    ON langgraph.checkpoints USING btree (thread_id);

CREATE INDEX migration_test_events_run_id_idx
    ON public.migration_test_events USING btree (run_id);
