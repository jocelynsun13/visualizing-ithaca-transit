require 'pg'
require 'json'

exact_routes_sql = "SELECT trip_id, route_color, gtfs_shape_lines.route_id, lon, lat FROM gtfs_shape_lines, (SELECT trip_id, route_id, ST_X(geom) as lon, ST_Y(geom) as lat FROM ( SELECT gtfs_trips.route_id, current_stops.trip_id, ST_ClosestPoint(gtfs_shape_lines.geom, current_stops.geom) as geom FROM gtfs_shape_lines, gtfs_trips, ( SELECT DISTINCT ON (trip_id) gtfs_stop_times.trip_id, gtfs_stops.geom FROM gtfs_stop_times, gtfs_stops, (SELECT trip_id FROM gtfs_trips t WHERE t.start_time <= time '09:00' AND t.end_time >= time '09:00' ) AS active_trips WHERE gtfs_stop_times.trip_id = active_trips.trip_id AND gtfs_stop_times.stop_id = gtfs_stops.stop_id AND gtfs_stop_times.departure_time = time '09:00' ORDER BY trip_id, stop_sequence DESC ) AS current_stops WHERE gtfs_shape_lines.shape_id = gtfs_trips.shape_id AND gtfs_trips.trip_id = current_stops.trip_id AND gtfs_trips.service_id IN ('12','13','14','17')) AS t2) AS t3 WHERE t3.route_id = gtfs_shape_lines.route_id;"

interpolated_routes_sql = "SELECT trip_id, route_color, gtfs_shape_lines.route_id, lon, lat FROM gtfs_shape_lines, (SELECT trip_id, route_id, ST_X(geom) as lon, ST_Y(geom) as lat FROM (SELECT trip_id, route_id, departure_time, arrival_time, (arrival_time - departure_time) interval_length, ST_LineInterpolatePoint( ST_LineSubstring(geom, LEAST(start_percent, end_percent), GREATEST( start_percent, end_percent) ), EXTRACT( epoch FROM (time '09:00' - departure_time)) / EXTRACT( epoch from(arrival_time - departure_time)) ) as geom FROM (SELECT gtfs_trips.route_id, current_stops.trip_id, current_stops.departure_time, next_stops.arrival_time, ST_LineLocatePoint( gtfs_shape_lines.geom, ST_ClosestPoint(gtfs_shape_lines.geom, current_stops.geom)) start_percent, ST_LineLocatePoint( gtfs_shape_lines.geom, ST_ClosestPoint(gtfs_shape_lines.geom, next_stops.geom)) as end_percent, gtfs_shape_lines.geom FROM gtfs_shape_lines, gtfs_trips, (SELECT DISTINCT ON (trip_id) gtfs_stop_times.trip_id, gtfs_stop_times.departure_time, gtfs_stops.geom FROM gtfs_stop_times, gtfs_stops, (SELECT trip_id FROM gtfs_trips t WHERE t.start_time <= time '09:00' AND t.end_time >= time '09:00' ) AS active_trips WHERE gtfs_stop_times.trip_id = active_trips.trip_id AND gtfs_stop_times.stop_id = gtfs_stops.stop_id AND gtfs_stop_times.departure_time <= time '09:00' ORDER BY trip_id, stop_sequence DESC ) as current_stops, (SELECT DISTINCT ON (trip_id) gtfs_stop_times.trip_id, gtfs_stop_times.arrival_time, gtfs_stops.geom FROM gtfs_stop_times, gtfs_stops, (SELECT trip_id FROM gtfs_trips t WHERE t.start_time <= time '09:00' AND t.end_time >= time '09:00' ) AS active_trips WHERE gtfs_stop_times.trip_id = active_trips.trip_id AND gtfs_stop_times.stop_id = gtfs_stops.stop_id AND gtfs_stop_times.departure_time >= time '09:00' ORDER BY trip_id, stop_sequence ASC ) as next_stops WHERE gtfs_shape_lines.shape_id = gtfs_trips.shape_id AND gtfs_trips.trip_id = current_stops.trip_id AND gtfs_trips.trip_id = next_stops.trip_id AND departure_time != time '09:00' AND arrival_time >= time '09:00' AND gtfs_trips.service_id IN ('12','13','14','17') ) AS stop_percents WHERE departure_time != time '09:00' ) AS t2) AS t3 WHERE t3.route_id = gtfs_shape_lines.route_id;"

conn = PG.connect :dbname => 'TCAT_GTFS_db', :user => 'postgres'

positions = []

0.upto(23) do |i|
  h = (i + 3) % 24
  0.upto(59) do |m|
    t = "#{ h.to_s.rjust(2, '0') }:#{ m.to_s.rjust(2, '0') }"

    puts t

    p = conn.exec(exact_routes_sql.gsub('09:00',t)).values
    p += conn.exec(interpolated_routes_sql.gsub('09:00',t)).values

    positions << p
    
  end
end

positions.map! do |p|
  t = {}
  p.each do |trip|
    t[ "#{ trip[0] }.#{ trip[1] }.#{ trip[2] }" ] = [ trip[4].to_f, trip[3].to_f ]
  end
  t
end

File.open('DyPosition.json','wb') do |f|
  f.write( { start_time: 180, positions: positions } .to_json)
end