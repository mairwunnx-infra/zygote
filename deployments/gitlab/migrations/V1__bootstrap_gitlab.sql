DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${gitlabUser}') THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', '${gitlabUser}', '${gitlabPassword}');
  ELSE
    EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', '${gitlabUser}', '${gitlabPassword}');
  END IF;
END
$$;

ALTER DATABASE ${gitlabDb} OWNER TO ${gitlabUser};
ALTER SCHEMA public OWNER TO ${gitlabUser};
GRANT ALL ON SCHEMA public TO ${gitlabUser};

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS btree_gist;