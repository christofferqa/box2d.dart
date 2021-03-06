/*******************************************************************************
 * Copyright (c) 2015, Daniel Murphy, Google
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *  * Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 ******************************************************************************/

part of box2d;

//Point-to-point constraint
//Cdot = v2 - v1
//   = v2 + cross(w2, r2) - v1 - cross(w1, r1)
//J = [-I -r1_skew I r2_skew ]
//Identity used:
//w k % (rx i + ry j) = w * (-ry i + rx j)

//Angle constraint
//Cdot = w2 - w1
//J = [0 0 -1 0 0 1]
//K = invI1 + invI2

/**
 * A motor joint is used to control the relative motion between two bodies. A typical usage is to
 * control the movement of a dynamic body with respect to the ground.
 *
 * @author dmurph
 */
class MotorJoint extends Joint {

  // Solver shared
  final Vector2 _linearOffset = new Vector2.zero();
  double _angularOffset = 0.0;
  final Vector2 _linearImpulse = new Vector2.zero();
  double _angularImpulse = 0.0;
  double _maxForce = 0.0;
  double _maxTorque = 0.0;
  double _correctionFactor = 0.0;

  // Solver temp
  int _indexA = 0;
  int _indexB = 0;
  final Vector2 _rA = new Vector2.zero();
  final Vector2 _rB = new Vector2.zero();
  final Vector2 _localCenterA = new Vector2.zero();
  final Vector2 _localCenterB = new Vector2.zero();
  final Vector2 _linearError = new Vector2.zero();
  double _angularError = 0.0;
  double _invMassA = 0.0;
  double _invMassB = 0.0;
  double _invIA = 0.0;
  double _invIB = 0.0;
  final Matrix2 _linearMass = new Matrix2.zero();
  double _angularMass = 0.0;

  MotorJoint(IWorldPool pool, MotorJointDef def) : super(pool, def) {
    _linearOffset.setFrom(def.linearOffset);
    _angularOffset = def.angularOffset;

    _angularImpulse = 0.0;

    _maxForce = def.maxForce;
    _maxTorque = def.maxTorque;
    _correctionFactor = def.correctionFactor;
  }

  void getAnchorA(Vector2 out) {
    out.setFrom(_bodyA.position);
  }

  void getAnchorB(Vector2 out) {
    out.setFrom(_bodyB.position);
  }

  void getReactionForce(double inv_dt, Vector2 out) {
    out.setFrom(_linearImpulse).scale(inv_dt);
  }

  double getReactionTorque(double inv_dt) {
    return _angularImpulse * inv_dt;
  }

  /**
   * Set the target linear offset, in frame A, in meters.
   */
  void setLinearOffset(Vector2 linearOffset) {
    if (linearOffset.x != _linearOffset.x ||
        linearOffset.y != _linearOffset.y) {
      _bodyA.setAwake(true);
      _bodyB.setAwake(true);
      _linearOffset.setFrom(linearOffset);
    }
  }

  /**
   * Get the target linear offset, in frame A, in meters.
   */
  void getLinearOffsetOut(Vector2 out) {
    out.setFrom(_linearOffset);
  }

  /**
   * Get the target linear offset, in frame A, in meters. Do not modify.
   */
  Vector2 getLinearOffset() {
    return _linearOffset;
  }

  /**
   * Set the target angular offset, in radians.
   *
   * @param angularOffset
   */
  void setAngularOffset(double angularOffset) {
    if (angularOffset != _angularOffset) {
      _bodyA.setAwake(true);
      _bodyB.setAwake(true);
      _angularOffset = angularOffset;
    }
  }

  double getAngularOffset() {
    return _angularOffset;
  }

  /**
   * Set the maximum friction force in N.
   *
   * @param force
   */
  void setMaxForce(double force) {
    assert(force >= 0.0);
    _maxForce = force;
  }

  /**
   * Get the maximum friction force in N.
   */
  double getMaxForce() {
    return _maxForce;
  }

  /**
   * Set the maximum friction torque in N*m.
   */
  void setMaxTorque(double torque) {
    assert(torque >= 0.0);
    _maxTorque = torque;
  }

  /**
   * Get the maximum friction torque in N*m.
   */
  double getMaxTorque() {
    return _maxTorque;
  }

  void initVelocityConstraints(SolverData data) {
    _indexA = _bodyA._islandIndex;
    _indexB = _bodyB._islandIndex;
    _localCenterA.setFrom(_bodyA._sweep.localCenter);
    _localCenterB.setFrom(_bodyB._sweep.localCenter);
    _invMassA = _bodyA._invMass;
    _invMassB = _bodyB._invMass;
    _invIA = _bodyA._invI;
    _invIB = _bodyB._invI;

    final Vector2 cA = data.positions[_indexA].c;
    double aA = data.positions[_indexA].a;
    final Vector2 vA = data.velocities[_indexA].v;
    double wA = data.velocities[_indexA].w;

    final Vector2 cB = data.positions[_indexB].c;
    double aB = data.positions[_indexB].a;
    final Vector2 vB = data.velocities[_indexB].v;
    double wB = data.velocities[_indexB].w;

    final Rot qA = pool.popRot();
    final Rot qB = pool.popRot();
    final Vector2 temp = pool.popVec2();
    Matrix2 K = pool.popMat22();

    qA.setAngle(aA);
    qB.setAngle(aB);

    // Compute the effective mass matrix.
    // _rA = b2Mul(qA, -_localCenterA);
    // _rB = b2Mul(qB, -_localCenterB);
    _rA.x = qA.c * -_localCenterA.x - qA.s * -_localCenterA.y;
    _rA.y = qA.s * -_localCenterA.x + qA.c * -_localCenterA.y;
    _rB.x = qB.c * -_localCenterB.x - qB.s * -_localCenterB.y;
    _rB.y = qB.s * -_localCenterB.x + qB.c * -_localCenterB.y;

    // J = [-I -r1_skew I r2_skew]
    // [ 0 -1 0 1]
    // r_skew = [-ry; rx]

    // Matlab
    // K = [ mA+r1y^2*iA+mB+r2y^2*iB, -r1y*iA*r1x-r2y*iB*r2x, -r1y*iA-r2y*iB]
    // [ -r1y*iA*r1x-r2y*iB*r2x, mA+r1x^2*iA+mB+r2x^2*iB, r1x*iA+r2x*iB]
    // [ -r1y*iA-r2y*iB, r1x*iA+r2x*iB, iA+iB]
    double mA = _invMassA,
        mB = _invMassB;
    double iA = _invIA,
        iB = _invIB;

    double a11 = mA + mB + iA * _rA.y * _rA.y + iB * _rB.y * _rB.y;
    double a21 = -iA * _rA.x * _rA.y - iB * _rB.x * _rB.y;
    double a12 = a21;
    double a22 = mA + mB + iA * _rA.x * _rA.x + iB * _rB.x * _rB.x;

    K.setValues(a11, a21, a12, a22);
    _linearMass.setFrom(K);
    _linearMass.invert();

    _angularMass = iA + iB;
    if (_angularMass > 0.0) {
      _angularMass = 1.0 / _angularMass;
    }

    // _linearError = cB + _rB - cA - _rA - b2Mul(qA, _linearOffset);
    Rot.mulToOutUnsafe(qA, _linearOffset, temp);
    _linearError.x = cB.x + _rB.x - cA.x - _rA.x - temp.x;
    _linearError.y = cB.y + _rB.y - cA.y - _rA.y - temp.y;
    _angularError = aB - aA - _angularOffset;

    if (data.step.warmStarting) {
      // Scale impulses to support a variable time step.
      _linearImpulse.x *= data.step.dtRatio;
      _linearImpulse.y *= data.step.dtRatio;
      _angularImpulse *= data.step.dtRatio;

      final Vector2 P = _linearImpulse;
      vA.x -= mA * P.x;
      vA.y -= mA * P.y;
      wA -= iA * (_rA.x * P.y - _rA.y * P.x + _angularImpulse);
      vB.x += mB * P.x;
      vB.y += mB * P.y;
      wB += iB * (_rB.x * P.y - _rB.y * P.x + _angularImpulse);
    } else {
      _linearImpulse.setZero();
      _angularImpulse = 0.0;
    }

    pool.pushVec2(1);
    pool.pushMat22(1);
    pool.pushRot(2);

    // data.velocities[_indexA].v = vA;
    data.velocities[_indexA].w = wA;
    // data.velocities[_indexB].v = vB;
    data.velocities[_indexB].w = wB;
  }

  void solveVelocityConstraints(SolverData data) {
    final Vector2 vA = data.velocities[_indexA].v;
    double wA = data.velocities[_indexA].w;
    final Vector2 vB = data.velocities[_indexB].v;
    double wB = data.velocities[_indexB].w;

    double mA = _invMassA,
        mB = _invMassB;
    double iA = _invIA,
        iB = _invIB;

    double h = data.step.dt;
    double inv_h = data.step.inv_dt;

    final Vector2 temp = pool.popVec2();

    // Solve angular friction
    {
      double Cdot = wB - wA + inv_h * _correctionFactor * _angularError;
      double impulse = -_angularMass * Cdot;

      double oldImpulse = _angularImpulse;
      double maxImpulse = h * _maxTorque;
      _angularImpulse = MathUtils.clampDouble(
          _angularImpulse + impulse, -maxImpulse, maxImpulse);
      impulse = _angularImpulse - oldImpulse;

      wA -= iA * impulse;
      wB += iB * impulse;
    }

    final Vector2 Cdot = pool.popVec2();

    // Solve linear friction
    {
      // Cdot = vB + b2Cross(wB, _rB) - vA - b2Cross(wA, _rA) + inv_h * _correctionFactor *
      // _linearError;
      Cdot.x = vB.x +
          -wB * _rB.y -
          vA.x -
          -wA * _rA.y +
          inv_h * _correctionFactor * _linearError.x;
      Cdot.y = vB.y +
          wB * _rB.x -
          vA.y -
          wA * _rA.x +
          inv_h * _correctionFactor * _linearError.y;

      final Vector2 impulse = temp;
      _linearMass.transformed(Cdot, impulse);
      impulse.negate();
      final Vector2 oldImpulse = pool.popVec2();
      oldImpulse.setFrom(_linearImpulse);
      _linearImpulse.add(impulse);

      double maxImpulse = h * _maxForce;

      if (_linearImpulse.length2 > maxImpulse * maxImpulse) {
        _linearImpulse.normalize();
        _linearImpulse.scale(maxImpulse);
      }

      impulse.x = _linearImpulse.x - oldImpulse.x;
      impulse.y = _linearImpulse.y - oldImpulse.y;

      vA.x -= mA * impulse.x;
      vA.y -= mA * impulse.y;
      wA -= iA * (_rA.x * impulse.y - _rA.y * impulse.x);

      vB.x += mB * impulse.x;
      vB.y += mB * impulse.y;
      wB += iB * (_rB.x * impulse.y - _rB.y * impulse.x);
    }

    pool.pushVec2(3);

    // data.velocities[_indexA].v.set(vA);
    data.velocities[_indexA].w = wA;
    // data.velocities[_indexB].v.set(vB);
    data.velocities[_indexB].w = wB;
  }

  bool solvePositionConstraints(SolverData data) {
    return true;
  }
}
