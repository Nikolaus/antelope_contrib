Dbptr dbform_working_view(Dbptr, Pf *, char *);
int dbpmel_process(Dbptr, Tbl *, Pf *);
Hypocenter db_load_initial(Dbptr,int);

int dbpmel_save_results(Dbptr, int, int *,Hypocenter *,
	Tbl **, Pf *);
void dbpmel_save_sc(int, Dbptr, SCMatrix *,Pf *);
int hypo_is_bad(Hypocenter *);

