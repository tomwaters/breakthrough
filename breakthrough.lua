-- breakthrough: 
-- a rebound remix
-- llllllll.co/t/breakthrough
--
-- key1: shift^
-- key2: add/^remove orb
-- key3: select next orb
-- enc2: rotate orb^s
-- enc3: accelerate orb^s
--
-- key1 + key3: game mode!
-- enc3: move
--
-- by tomw
-- rebound by nf, okyeron

local cs = require 'controlspec'
local util = require 'util'
local MusicUtil = require 'musicutil'

engine.name = "PolyPerc"

local m = midi.connect()

local ii_options = {"off", "ii jf"}

local bricks_wide = 8
local bricks_high = 4

local screen_width = 128
local brick_margin = 3
local brick_height = 6
local brick_width = ((screen_width - brick_margin) / bricks_wide) - brick_margin

local bricks = {}
local balls = {}
local cur_ball = 0
local scale_notes = {}
local note_queue = {}
local note_off_queue = {}

local min_note = 0
local max_note = 127

local shift = false

--0 = not game mode, 1 = game play, 2 = game over
local game_state = 0
local game_score = 0
local game_level = 0
local game_pos = 0
local game_width = 0

function init()
  screen.aa(1)
  
  local u = metro.init()
  u.time = 1/60
  u.count = -1
  u.event = update
  u:start()
  
  cs.CLOCKDIV = cs.new(1/4,16,'lin',0.5,4,'')
  params:add_control("step_div", "clock division", cs.CLOCKDIV)
  
  params:add_option("ii", "ii", ii_options, 1)
  params:set_action("ii", function() crow.ii.pullup(true) crow.ii.jf.mode(1) end)
  params:add_separator()
  
  local scales = {}
  for i=1,#MusicUtil.SCALES do
    scales[i] = MusicUtil.SCALES[i].name
  end
  params:add_option("scale", "scale", scales)
  params:set_action("scale", build_scale)

  params:add{type = "number", id = "root_note", name = "root note",
    min = 0, max = 127, default = 60, formatter = function(param) return MusicUtil.note_num_to_name(param:get(), true) end,
    action = function() build_scale() end}
  
  params:add_number("octaves", "octaves", 1, 9, 2)
  params:set_action("octaves", build_scale)

  local wall_options = {"None", "All", "Selected"}
  params:add{type = "number", id = "walls", name = "wall note orbs", 
    min = 1, max = 3, default = 3, formatter = function(param) return wall_options[param:get()] end}
  
  params:add{type= "number", id = "density", name = "brick density",
    min = 10, max = 100, default = 100, formatter = function(param) return param:get().."%" end}

  params:add{type= "number", id = "super orb", name = "super orb",
    min = 0, max = 100, default = 10, formatter = function(param) return param:get().."%" end}
  params:add_separator()  

  cs.AMP = cs.new(0,1,'lin',0,0.5,'')
  params:add_control("amp", "amp", cs.AMP)
  params:set_action("amp",
  function(x) engine.amp(x) end)

  cs.PW = cs.new(0,100,'lin',0,60,'%')
  params:add_control("pw", "pw", cs.PW)
  params:set_action("pw",
  function(x) engine.pw(x/100) end)

  cs.REL = cs.new(0.1,3.2,'lin',0,0.8,'s')
  params:add_control("release", "release", cs.REL)
  params:set_action("release",
  function(x) engine.release(x) end)

  cs.CUT = cs.new(50,5000,'exp',0,1500,'hz')
  params:add_control("cutoff", "cutoff", cs.CUT)
  params:set_action("cutoff",
  function(x) engine.cutoff(x) end)

  cs.GAIN = cs.new(0,4,'lin',0,1,'')
  params:add_control("gain", "gain", cs.GAIN)
  params:set_action("gain",
  function(x) engine.gain(x) end)
  
  params:bang()
  
  reset()
  clock.run(pulse)
end

function init_bricks()
  local brick_strength = game_state == 0 and 4 or 1
  local root = params:get("root_note")
  local scale = MusicUtil.SCALES[params:get("scale")]
  local max_rand_note = root + #scale.intervals * params:get("octaves")
  local brick_density = params:get("density") / 100
  
  for x=1, bricks_wide do
    bricks[x] = {}
    for y=1, bricks_high do
	    bricks[x][y] = {
	      s = math.random() <= brick_density and brick_strength or 0,
        n = math.random(root + 1, max_rand_note),
        r = false
	    }
    end
  end
end

function pulse()
  while true do
    clock.sync(1/params:get("step_div"))
    play_notes()
  end
end

function build_scale()
  scale_notes = MusicUtil.generate_scale(params:get("root_note"), params:get("scale"), params:get("octaves"))
end

function redraw() 
  screen.clear()
  screen.line_width(1)
  
  for y=1, bricks_high do
	  local start_y = ((y - 1) * (brick_height + brick_margin)) + brick_margin
    for x=1, bricks_wide do
	    local start_x = ((x - 1) * (brick_width + brick_margin)) + brick_margin
	    screen.level(bricks[x][y].s * (game_state == 0 and 3 or 12))
	    screen.rect(start_x, start_y, brick_width, brick_height)
	    screen.fill()
	  end
  end
  
  for i=1,#balls do
    drawball(balls[i], i == cur_ball)
  end
  
  if game_state > 0 then
    local half_paddle = game_width / 2
    screen.line_width(2)
    screen.move(game_pos - half_paddle, 62)
    screen.line(game_pos + half_paddle, 62)
    screen.stroke()
  end

  if game_state == 2 then
    screen.level(4)
    screen.rect(6, 6, screen_width - 12, 52)
    screen.fill()

    screen.level(15)
    screen.move(64, 20)
    screen.text_center("Game Over!")
    screen.move(64, 30)
    screen.text_center("You Reached Level: " .. game_level)
    screen.move(64, 40)
    screen.text_center("You Scored: " .. game_score)
    screen.move(64, 50)
    screen.text_center("Press K3 to try again")
  end

  screen.update()
end

function update()
  for i=1,#balls do
    updateball(i)
  end
  redraw()
end

function enc(n,d)
  if n == 2 and game_state == 0 then
    -- rotate
    for i=1,#balls do
      if shift or i == cur_ball then
        balls[i].a = balls[i].a - d/10
      end
    end
  elseif n == 3 then
    if game_state == 0 then
      -- accelerate
      for i=1,#balls do
        if shift or i == cur_ball then
          balls[i].v = balls[i].v + d/10
        end
      end
    else
      -- move paddle
      local half_paddle = game_width / 2
      game_pos = util.clamp(game_pos + d, half_paddle, screen_width - half_paddle)
    end
  end
end

function key(n,z)
  if n == 1 then
    -- shift
    shift = z == 1
  elseif n == 2 and z == 1 and game_state == 0 then
    if shift then
      -- remove ball
      table.remove(balls, cur_ball)
      if cur_ball > #balls then
        cur_ball = #balls
      end
    else
      -- add ball
      table.insert(balls, newball())
      cur_ball = #balls
    end
  elseif n == 3 and z == 1 then
    if shift then
      if game_state == 0 then
        gamemode()
      else
        game_state = 0
        reset()
      end
    elseif game_state == 2 then
      gamemode()
    elseif #balls > 0 then
      -- select next ball
      cur_ball = cur_ball%#balls+1
    end
  end
end

function reset()
  init_bricks()
  balls = {}
  table.insert(balls, newball())
  cur_ball = #balls
end

function gamemode()
  game_state = 1
  game_score = 0
  game_level = 1
  game_width = 30
  game_pos = 64
  reset()
end

function gamelevelup()
  game_score = game_score + 10
  game_level = game_level + 1
  game_width = util.clamp(game_width - 6, 6, 30)
  balls[1].v = util.clamp(balls[1].v + 0.1, 0, 2)
end

function gameover()
  game_state = 2
  balls = {}
end

function newball()
  return {
    x = 64,
    y = 60,
    v = game_state == 0 and 0.5*math.random()+0.5 or 0.6,
    a = game_state == 0 and math.random()*2*math.pi or 1,
    s = false
  }
end

function drawball(b, hilite)
  screen.level(hilite and 15 or 5)
  screen.circle(b.x, b.y, hilite and 2 or 1.5)
  screen.fill()
end

--- check if all bricks are clear
function allclear()
  for y=1, bricks_high do
	  for x=1, bricks_wide do
	    if bricks[x][y].s > 0 then 
	      return false
	    end
    end
  end
  return true
end

function updateball(i)
  local b = balls[i]
  local oldX = b.x
  local oldY = b.y
  b.x = b.x + math.sin(b.a)*b.v
  b.y = b.y + math.cos(b.a)*b.v

  local minx = 2
  local miny = 2
  local maxx = 126
  local maxy = game_state == 0 and 62 or 60
  
  if b.y >= maxy or b.y <= miny then
    local half_paddle = game_width / 2

    if game_state == 0 or b.y <= miny or (b.y >= maxy and b.x >= game_pos - half_paddle and b.x <= game_pos + half_paddle) then
      b.y = b.y >= maxy and maxy or miny
      b.a = math.pi - b.a
      if not b.r and (params:get("walls") == 2 or (params:get("walls") == 3 and i == cur_ball)) then
        enqueue_note(1)
      end
    else
      gameover()
    end
  elseif b.x >= maxx or b.x <= minx then
    b.x = b.x >= maxx and maxx or minx
    b.a = 2*math.pi - b.a
  elseif b.y > (bricks_high + 1) * (brick_height + brick_margin) then
    b.r = false
    b.s = math.random() <= (params:get("super orb") / 100)
  elseif not b.r and b.y <= bricks_high * (brick_height + brick_margin) then

    -- figure out which brick we might be in
	  local brick_x = util.clamp(math.ceil(b.x / (brick_width + brick_margin)), 1, bricks_wide)
    local brick_y = util.clamp(math.ceil(b.y / (brick_height + brick_margin)), 1, bricks_high)
    if bricks[brick_x][brick_y].s > 0 then
      enqueue_note(bricks[brick_x][brick_y].n)

      -- reduce strength of hit brick
      bricks[brick_x][brick_y].s = b.s and 0 or bricks[brick_x][brick_y].s - 1
      if bricks[brick_x][brick_y].s <= 0 then
        bricks[brick_x][brick_y].s = 0
        
        if game_state > 0 then
          game_score = game_score + 1
        end

        -- if all bricks are clear
        if allclear() then
          for n=1,#balls do
            balls[n].r = true
          end
          init_bricks()
          
          if game_state > 0 then
            gamelevelup()
          end
        end
      end

      -- if this isn't a super ball, bounce off the brick
      if b.s == false then
        local brickYMax = (brick_height + brick_margin) * brick_y
        if oldY <= brickYMax and oldY >= brickYMax - brick_height then
          b.a = 2*math.pi - b.a  
        else
          b.a = math.pi - b.a
        end
        
        b.x = oldX
        b.y = oldY
      end
    end
  end
end

function enqueue_note(note)
  local n = math.max(min_note, math.min(max_note, note))
  table.insert(note_queue, n)
end

function play_notes()
  -- send note off for previously played notes
  while #note_off_queue > 0 do
    m:send({type='note_off', note=table.remove(note_off_queue)})
  end
  -- play queued notes
  while #note_queue > 0 do
    local n = table.remove(note_queue)
    n = MusicUtil.snap_note_to_array(n, scale_notes)
    engine.hz(MusicUtil.note_num_to_freq(n))
    m:send({type='note_on', note=n})
    if params:get("ii") == 2 then
      crow.ii.jf.play_note((n - 60) / 12, 5)
    end
    table.insert(note_off_queue, n)
  end
end
