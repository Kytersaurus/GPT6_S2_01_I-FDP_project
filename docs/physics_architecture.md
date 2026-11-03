# Bad Piggies FPGA Physics Architecture

The physics engine (`physics_engine.v`) is a rigid-body solver running in fixed-point arithmetic (Q12.8 format) at 100 MHz. Because the FPGA has strict constraints (no single-cycle divisions, limited multipliers), the engine is built as a sequential Finite State Machine (FSM) that calculates forces, divides by mass, calculates torque, and resolves collisions over multiple clock cycles.

---

## 1. The Physics Pipeline (Execution Flow)

Every update frame, the FSM steps through a strict sequence of calculations before handing the proposed movement to the collision engine.

```mermaid
flowchart TD
    Start([Step Start]) --> Sample[Sample Inputs\nMass, Build Grid, Inputs]
    
    subgraph Linear Forces
        Sample --> Vert[Calculate Vertical Forces\nGravity, Balloon Lift]
        Vert --> Thrust[Calculate Thrust\nFans, Rockets]
        Thrust --> Slope[Calculate Slope Gravity\nDownhill Acceleration]
        Slope --> Friction[Calculate Friction & Drag]
    end
    
    subgraph Velocity Integration
        Friction --> Div1[16-cycle Serial Divider\na = F / m]
        Div1 --> Vel[Clamp Maximum Velocity]
    end
    
    subgraph Rotational Dynamics
        Vel --> Moments[vehicle_moments helper\nCalculate COM & Torque]
        Moments --> Rot[Integrate Angular Velocity & Tilt]
    end

    subgraph Collision Handshake
        Rot --> Pos[Integrate Position\nx += v_x, y += v_y]
        Pos --> Send[Send Proposed Pose to Collision Engine]
        Send -. SAT Checking .-> Wait[Wait for Collision Response]
        Wait --> Commit[Commit Corrected Position, Tilt, Grounded State]
    end
    
    Commit --> End([Idle / Wait for Next Frame])
```

---

## 2. Force & Velocity Calculation

The engine breaks down forces into horizontal and vertical components, ensuring they are summed sequentially to save logic.

1. **Vertical Base:** Gravity adds downward acceleration `32`; each intact balloon subtracts acceleration `24`. The former spring/jump impulse is removed. BTNL is reserved, and legacy `jump_press` ports are inert.
2. **Propulsion:** 
   - **Engines** apply force to wheels touching the ground.
   - **Horizontal fans** keep their existing world-horizontal force of `64` per enabled intact fan, with the corrected facing sign.
   - **Future downward-blowing fans** supply world-up force `256` each (`FAN_LIFT_FORCE_SHIFT=8`). `live_lift_fan_count` supplies the surviving count, gated by `fan_enabled`; these fans must be excluded from horizontal `fan_balance`. The nine-bit `fan_lift_mask` identifies their cells for moments. Both inputs default to zero, and the hardware top ties them low until the item and sprite are implemented.
   - **Rockets** rotate their body-fixed thrust using `rotation_sin` and `rotation_cos`; the production top uses force `1024`. Their X/Y force components are accumulated sequentially.
3. **Slope Gravity:** Grounded ramp acceleration uses the measured slope and remaining downward acceleration. Fan lift is divided by mass and reduces both slope gravity and the support reaction; net upward lift releases ground support.
4. **Mass Division:** Acceleration is $a = F / m$. Because division (`/`) consumes massive FPGA resources, the engine routes total force and total mass through a custom restoring divider (`signed_divider16.v`), which takes 16 clock cycles to produce the acceleration.
5. **Momentum & Friction:** The vehicle's momentum is checked against rolling drag (`wheel_drag`) or scraping drag (`scrape_drag`). Friction can stop the vehicle but will never push it backward.

---

## 3. Moments & Rotational Physics

Rotational physics uses the `vehicle_moments` module appended to `physics_engine.v`. There is no separate `vehicle_moments.v` design source. COM, force projections and pivot corrections reuse the helper's serial multiplier and divider; fan lift adds no independent multiplier, divider or memory.

```mermaid
flowchart LR
    Grid[3x3 Build Grid] --> COM[Calculate Center of Mass]
    COM --> ForceArm[Calculate Lever Arms\nDistance from COM to Parts]
    ForceArm --> Cross[Cross Product\nTorque = r x F]
    Cross --> Div2[Divide Total Torque by Mass]
    Div2 --> Accel[Angular Acceleration]
    
    Support[Ground Contacts] --> Pivot{Is vehicle toppling\nover an edge?}
    Pivot -- Yes --> P_Edge[Calculate pivot arc around edge]
    Pivot -- No --> P_COM[Rotate normally around COM]
```

### Center of Mass (COM)
The 3x3 vehicle grid is scanned. Each part has a specific weight (e.g., Engine = 3, Pig = 2, Wheel = 1). The COM is found by averaging the positions of all active parts weighted by their mass.

### Torque Calculation
For each active fan or rocket, the engine calculates its distance vector (`arm_x`, `arm_y`) from the COM. Torque is `rx*Fy - ry*Fx`. Thus an off-centre lift fan uses its world-horizontal arm and upward force to turn the body; a centred lift fan supplies lift without torque. The total torque is divided by the mass-scaled inertia to determine angular acceleration. Wheel drive remains translational and supplies no moment.

### Edge Pivoting
If the vehicle is unbalanced over its actual contact span, the engine proposes rotation around the physical contact edge. On ramps the support test uses the terrain normal, not a vertical-only reaction. Airborne rotation uses the COM. Collision checks the complete rotated pose and rejects unsafe turns; angular damping brings unpowered spin toward rest.

---

## 4. Terrain & Slope Interaction

The terrain is not perfectly smooth; it is a rasterized bitmap. The physics engine and collision engine (`rotating_map_collision_engine.v`) work together to handle slopes smoothly.

1. **Terrain Probing:** The collision engine uses left and right probes to measure the ground beneath the vehicle.
2. **Gradient Feedback:** It reports the slope back to the physics engine as a `dy/dx` ratio (e.g., Q4.4 format).
3. **Settling & Snapping:**
   - **Alpha-Beta Filter:** To prevent the camera/graphics from jittering vertically as the vehicle moves over 2-pixel staircase terrain, the visual output (`display_y`) is smoothed over time.
   - **Alignment:** When grounded, the physics FSM gently rotates the proposed vehicle tilt towards the measured slope angle (1 step per frame) until it aligns flush with the hill. 
   - **Slope Acceleration:** The measured slope directly drives the "Slope Gravity" horizontal force calculation, causing unpowered vehicles to coast downhill.

## 5. TNT damage

TNT damage is separate from the force solver. `tnt_controller` holds content/frame damage masks until the builder accepts them, then allows world checks after the updated masks settle. The builder protects the pig and its supporting frame; other nearby parts and frames can be destroyed without changing the saved build or stock. The current explosion has animation and sound but no velocity kick.
