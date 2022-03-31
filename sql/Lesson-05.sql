
/* Lesson 04 practice SQL in PostGIS */
/* February, 2017 */

/*

IMPORTANT

This lesson uses a very large dataset. Since we're working with only Kentucky let's subset the data:

    1. After loading "FPA_FOD_20150323 Fires" layer in QGIS, right-click the layer in and "Filter..."
    with the following query: "STATE" = 'KY'
    2. Select all point features in the Map Canvas
    3. Load the layer into your PostGIS database and Rename the layer "ky_wildfires" and enable
    "Import only selected features"
    4. On import, make sure the target SRID is 3089, "Convert field names to lowercase", select "Create spatial index".

*/

/*********************************************************************************************/



/*********************************************************************************************/

/* Create Kentucky polygon layer from census download */

create table
	ky_state
as

select
	*
from
	cb_2016_us_state_500k

where
	stusps = 'KY'


/*********************************************************************************************/

/* Delete id field */

alter table
    ky_state
drop column
    id

/*********************************************************************************************/

/* Create new id field as a Primary key (autincrementing and always unique) */

alter table
    ky_state
add column
    id SERIAL PRIMARY KEY

/*********************************************************************************************/
/*********************************************************************************************/

/*

Load custom function to create hexagon grids in PostGIS.
Copy and paste this SQL in DB Manager and Execute:
https://raw.githubusercontent.com/CartoDB/cartodb-postgresql/master/scripts-available/CDB_Hexagon.sql

Useage: CDB_HexagonGrid(geomtery, side length of hexagon)
Units will be the in the input SRID

*/

/*********************************************************************************************/
/*********************************************************************************************/


/* Make hexagonal grid with a 5-mile diameter per hexagon */

select
     CDB_HexagonGrid(st_envelope(st_transform(geom,3089)), 2.5*5280) as geom
/*

Function requires geometry field and length of side. Units will be the in the input SRID.
We are nesting two functions inside  CDB_HexagonGrid() function.
The first function, st_transform(geom, 3089) projects to a Kentucky CRS.
The next function, st_enevelope(), finds the geometry of bounding rectangle for on layer.

*/

from
	ky_state

/*********************************************************************************************/

/* Create table with hexagonal grid with a 5-mile diameter per hexagon */

create table
    hexgrid_5mi
as

select
     CDB_HexagonGrid(st_envelope(st_transform(geom,3089)), 2.5*5280) as geom

from
	ky_state


/*********************************************************************************************/

/* Create new id field as a Primary key (autincrementing and always unique) */

alter table
    hexgrid_5mi
add column
    id SERIAL PRIMARY KEY


/*********************************************************************************************/

/* Project wildfire layer to a EPSG: 3089 */

/*********************************************************************************************/


/* Test spatial join wildfire points to 5-mile hexagonal grid */


select
    count(ky_wildfires.id) as count,
    round((sum(ky_wildfires.fire_size)/640)::numeric,4) as fires_area_sq_mi,
    hexgrid_5mi.geom
from
    hexgrid_5mi
join
    ky_wildfires
on
    st_intersects(hexgrid_5mi.geom, ky_wildfires.geom)
group by
    hexgrid_5mi.id
order by
     fires_area_sq_mi desc



/*********************************************************************************************/


/* Spatial join wildfire points to 5-mile hexagonal grid and create table */

create table
    wildfire_by_5mile_hexagon
as

select
    count(ky_wildfires.id) as count,
    round((sum(ky_wildfires.fire_size)/640)::numeric,4) as fires_area_sq_mi,
    hexgrid_5mi.geom
from
    hexgrid_5mi
join
    ky_wildfires
on
    st_intersects(hexgrid_5mi.geom, ky_wildfires.geom)
group by
    hexgrid_5mi.id
order by
     fires_area_sq_mi desc

/*********************************************************************************************/

/* Create new id field as a Primary key (autincrementing and always unique) */

alter table
     wildfire_by_5mile_hexagon
add column
    id SERIAL PRIMARY KEY


/*********************************************************************************************/


/* Make table with summary statistics */

create table summary_stats as

select
    avg(fires_area_sq_mi) as "Average square miles burned by hexagon",
    sum(fires_area_sq_mi) as "Total cumulative sq mi burned",
    max(fires_area_sq_mi) as "Largest etc."
from
    wildfire_by_5mile_hexagon

/*********************************************************************************************/






/*********************************************************************************************/

/* EXTRA: Without the where clause, this is a solution to Lab 3. */

/* Extract Kentucky counties and join population estimates and create new table from selection. */

/* Intersect fires to county polygons
/* solution? */

Create table
    ky_county_pop
as

select
    cb_2015_us_county_500k.*,PopulationEstimates.*
from
    cb_2015_us_county_500k
join
    PopulationEstimates
on
    (cb_2015_us_county_500k.geoid = PopulationEstimates.FIPS)
where
    cb_2015_us_county_500k.geoid like '21%'



		/*** Addendum 2 ***/

		/**** Create Functions to analyze wildfire by cause ****/


		create or replace function
		  fire_by_cause(cause varchar, acres real)
		returns table
		  (
		  id int8,
		  geom geometry(Point,4269),
		  cause_action varchar,
		  size_ac float8,
		  name varchar,
		  report_unit_name varchar,
		  discover_date varchar
		  )
		as
		$$
		BEGIN
		return query select
		  us_wildfires.id,
		  us_wildfires.geom as geom,
		  us_wildfires.stat_cause_descr,
		  us_wildfires.fire_size,
		  us_wildfires.fire_name,
		  us_wildfires.nwcg_reporting_unit_name,
		  us_wildfires.discovery_date
		from
		  public.us_wildfires
		where
		  fire_size > acres
		and
		  stat_cause_descr like cause
		order by
		  fire_size desc;
		END;
		$$
		language 'plpgsql';

		/**** Example of use ****/

		select
		  *
		from
		  fire_by_cause('%Arson%', 1000);

		create table
		    arson_larger_than_1000
		as
		select
		  *
		from
		  fire_by_cause('%Arson%', 1000);

		alter table
		  arson_larger_than_1000
		add primary key (id),
		alter column geom TYPE geometry(Point,4269);
