--!nocheck
local TweenService = game:GetService("TweenService");

-- Imports
local Trove = require(script.Parent.Trove);

-- Types
export type BezierPoint = {
	Type: string;
	Point: Vector3 | BasePart;
}

--[=[
    @within BezierTween
    @type BezierTween () -> BezierTween
]=]
export type BezierTween = typeof(setmetatable({} :: BezierTweenArguments, {} :: Object));

--[=[
	@within BezierTween
	@interface BezierTweenArguments
	@field Points {BezierPoint}
	@field LengthIterations number
	@field LengthIndeces {[number]: {number}}
	@field Length number
	@field _pointConnections {[Vector3 | BasePart]: Trove.Trove}
	@field _trove Trove.Trove
]=]
export type BezierTweenArguments = {
	Points: {BezierPoint},
	LengthIterations: number,
	LengthIndeces: {[number]: {number}},
	Length: number,
	_pointConnections: {[Vector3 | BasePart]: Trove.Trove},
	_trove: Trove.Trove,
}

--[=[
	@within BezierTween
	@interface Object
	@field AddBezierPoint (self: BezierTween, point: Vector3 | BasePart, index: number?) -> ()
	@field ChangeBezierPoint (self: BezierTween, index: number, point: Vector3 | BasePart) -> ()
	@field GetAllPoints (self: BezierTween) -> {Vector3}
	@field GetPoint (self: BezierTween, i: number) -> Vector3?
	@field RemoveBezierPoint (self: BezierTween, index: number) -> ()
	@field _updateBezierLength (self: BezierTween) -> ()
	@field CalculatePositionAt (self: BezierTween, t: number) -> Vector3
	@field CalculatePositionRelativeToLength (self: BezierTween, t: number) -> Vector3
	@field CalculateDerivativeAt (self: BezierTween, t: number) -> Vector3?
	@field CalculateDerivativeRelativeToLength (self: BezierTween, t: number) -> Vector3
	@field _applyTween (self: BezierTween, object: {any}, propertyTable: {any}, t: number, relativeToLength: boolean?) -> ()
	@field CreateTween (self: BezierTween, object: Instance | {[any]: any}, propertyTable: {any}, tweenInfo: TweenInfo, relativeToLength: boolean?) -> Tween
	@field Destroy (self: BezierTween) -> ()
	@field new (...Vector3 | BasePart) -> BezierTween
]=]
type Object = {
	__index: Object,
	AddBezierPoint: (self: BezierTween, point: Vector3 | BasePart, index: number?) -> (),
	ChangeBezierPoint: (self: BezierTween, index: number, point: Vector3 | BasePart) -> (),
	GetAllPoints: (self: BezierTween) -> {Vector3},
	GetPoint: (self: BezierTween, i: number) -> Vector3?,
	RemoveBezierPoint: (self: BezierTween, index: number) -> (),
	_updateBezierLength: (self: BezierTween) -> (),
	CalculatePositionAt: (self: BezierTween, t: number) -> Vector3,
	CalculatePositionRelativeToLength: (self: BezierTween, t: number) -> Vector3,
	CalculateDerivativeAt: (self: BezierTween, t: number) -> Vector3?,
	CalculateDerivativeRelativeToLength: (self: BezierTween, t: number) -> Vector3,
	_applyTween: (self: BezierTween, object: {any}, propertyTable: {any}, t: number, relativeToLength: boolean?) -> (),
	CreateTween: (self: BezierTween, object: Instance | {[any]: any}, propertyTable: {any}, tweenInfo: TweenInfo, RelativeToLength: boolean?) -> Tween,
	Destroy: (self: BezierTween) -> (),
	new: (...Vector3 | BasePart) -> BezierTween,
}

--[=[
	@class BezierTween
]=]
local BezierTween: Object = {} :: Object;
BezierTween.__index = BezierTween;

-- Constants
local DEFAULT_TWEEN_TIME = 10;
local DEFAULT_TWEEN_EASING_STYLE = Enum.EasingStyle.Sine;
local DEFAULT_TWEEN_EASING_DIRECTION = Enum.EasingDirection.Out;
local DEFAULT_TWEEN_REPEAT_COUNT = 0;
local DEFAULT_TWEEN_REVERSES = false;
local DEFAULT_TWEEN_DELAY = 0;
local VALID_TWEEN_PROPERTIES = {
	"number",
	"Vector2",
	"Vector3",
	"CFrame"
};

-- De Casteljau's algorithm implementation
local function deCasteljau(points: {BezierPoint}, t: number): Vector3
	local Q = {};

	for i = 1, #points do
		Q[i] = points[i];
	end;

	for k = 1, #points - 1 do
		for j = 1, #points - k do
			Q[j] = (1 - t) * Q[j] + t * Q[j + 1];
		end;
	end;

	return Q[1];
end

-- De Casteljau's algorithm derivative implementation
local function deCasteljauDerivative(points: {BezierPoint}, t: number): Vector3
	local n = #points - 1;

	-- If the curve is linear, its derivative is constant
	if (n == 1) then
		return points[2] - points[1];
	end;

	local Q = {};
	for i = 1, #points do
		Q[i] = points[i];
	end;

	-- Calculate the derivative with one less iteration than the curve
	for k = 1, n - 1 do
		for j = 1, n - k + 1 do
			Q[j] = (1 - t) * Q[j] + t * Q[j + 1];
		end;
	end;

	return n * (Q[2] - Q[1]);
end

-- Check if a property name is valid in the said object
local function ValidPropertyName(object: {any}, propertyName: string): boolean
	local Success, Value = pcall(function()
		return object[propertyName];
	end);

	if (Success and table.find(VALID_TWEEN_PROPERTIES, typeof(Value))) then
		return true;
	end;

	return false;
end

-- Our own very basic implementation of assert because Roblox refuses to fix theirs
local function SmartAssert(condition: boolean, message: string)
	if (not condition) then
		error(message, 2);
	end;
end

--[=[
	@param points {Vector3 | BasePart}

	Creates a new Bezier object with the given points added in order
]=]
function BezierTween.new(...: {Vector3 | BasePart})
	local self = setmetatable({} :: BezierTweenArguments, BezierTween);

	self.Points = {};
	self.LengthIterations = 1000;
	self.LengthIndeces = {};
	self.Length = 0;

	self._pointConnections = {};
	self._trove = Trove.new();

	for _, Point in pairs({...}) do
		SmartAssert(typeof(Point) == "Vector3" or (typeof(Point) == "Instance" and Point:IsA("BasePart")), "The Bezier.new(...) constructor only takes in Vector3s and BaseParts as inputs!");
		self:AddBezierPoint(Point);
	end;

	return self;
end

--[=[
	@param point Vector3 | BasePart
	@param index number?

	Adds a BezierPoint to the Bezier
	a BezierPoint can either be a Vector3 or a BasePart
	a Vector3 BezierPoint is static, while a BasePart BezierPoint changes if the BasePart's position changes
]=]
function BezierTween:AddBezierPoint(point, index)
	SmartAssert(point and (typeof(point) == "Instance" and point:IsA("BasePart")) or typeof(point) == "Vector3", `Bezier:AddBezierPoint() only accepts a Vector3 or BasePart as the first argument!`);
	SmartAssert(not index or type(index) == "number", `Bezier:AddBezierPoint() only accepts an integer as the second argument!`);

	local NewPoint: BezierPoint = {
		Type = typeof(point) == "Vector3" and "StaicPoint" or "BasePartPoint";
		Point = point;
	};

	-- Watch for removal or changes
	if (NewPoint.Type == "BasePartPoint") then
		if (not self._pointConnections[point]) then
			self._pointConnections[point] = Trove.new();
		end;

		local PointConnections = self._pointConnections[point];

		PointConnections:Add((point:: BasePart).Changed:Connect(function(prop)
			if (prop == "Position") then
				self:_updateBezierLength();
			end;
		end));

		PointConnections:Add((point:: BasePart).AncestryChanged:Connect(function(_, parent)
			if (parent == nil) then
				local pointIndex = table.find(self.Points, NewPoint);

				if (pointIndex) then
					table.remove(self.Points, pointIndex);
				end;

				-- Disconnect all connections if the point is removed
				PointConnections:Clean();
			end;
		end));
	end;

	if (index and type(index) == "number") then
		table.insert(self.Points, index, NewPoint);
	elseif (not index) then
		table.insert(self.Points, NewPoint);
	elseif (type(index) ~= "number") then
		error("Bezier:AddBezierPoint() only accepts an integer as the second argument!");
	end;

	self:_updateBezierLength();
end

--[=[
	@param index number
	@param p Vector3 | BasePart

	Changes a BezierPoint in the Bezier
	only works if the BezierPoint exists in the Bezier
]=]
function BezierTween:ChangeBezierPoint(index, point)
	SmartAssert(type(index) == "number", `Bezier:ChangeBezierPoint() only accepts a number index as the first argument!`);
	SmartAssert(point and (typeof(point) == "Instance" and point:IsA("BasePart")) or typeof(point) == "Vector3", `Bezier:ChangeBezierPoint() only accepts a Vector3 or BasePart as the second argument!`);

	local BezierPoint = self.Points[index];

	if (BezierPoint) then
		BezierPoint.Type = typeof(point) == "Vector3" and "StaicPoint" or "BasePartPoint";
		BezierPoint.Point = point;
		self:_updateBezierLength();
	else
		error(`Did not find BezierPoint at index {tostring(index)}!`);
	end;
end

--[=[
	@return {Vector3}

	Returns a table with vector3 control points of the Bezier
]=]
function BezierTween:GetAllPoints()
	local Points = self.Points;
	local NumberOfPoints = #Points;
	local NewPoints = {};

	for Index = 1, NumberOfPoints do
		local Point = self:GetPoint(Index);
		if (not Point) then
			warn(`Did not find a BezierPoint at index {tostring(Index)}!`);
			continue;
		end;
		table.insert(NewPoints, Point);
	end;

	return NewPoints;
end

--[=[
	@param i number

	Gets the BezierPoint of the Bezier at the index
]=]
function BezierTween:GetPoint(i)
	SmartAssert(type(i) == "number", `Bezier:GetPoint() only accepts a number index as the first argument!`);
	local Points = self.Points;

	SmartAssert(Points[i], `Did not find a BezierPoint at index {tostring(i)}!`);
	return typeof(Points[i].Point) == "Vector3" and Points[i].Point or Points[i].Point.Position;
end

--[=[
	@param index number

	Removes a BezierPoint from the Bezier
]=]
function BezierTween:RemoveBezierPoint(index)
	SmartAssert(type(index) == "number", `Bezier:RemoveBezierPoint() only accepts a number index as the first argument!`);
	SmartAssert(self.Points[index], `Did not find a BezierPoint at index {tostring(index)}!`);

	local Point = table.remove(self.Points, index);

	if (typeof(Point.Point) == "Instance" and Point.Point:IsA("BasePart")) then
		self._pointConnections[Point.Point]:Clean();
		self._pointConnections[Point.Point] = nil;
	end;

	self:_updateBezierLength();
end

--[=[
	@return (number, {{number, number, number}, {number, number, number}})

	Updates length of the Bezier
]=]
function BezierTween:_updateBezierLength()
	local Points = self:GetAllPoints();
	local Iterations = self.LengthIterations;

	if (#Points < 2) then
		return 0, {{0, 0, 0}, {0, 0, 0}};
	end;

	local Length = 0;
	local Sums = {};

	for Index = 1, Iterations do
		local Derivative = self:CalculateDerivativeAt((Index - 1) / (Iterations - 1));
		Length += Derivative.Magnitude * (1 / Iterations);
		table.insert(Sums, {((Index - 1) / (Iterations - 1)), Length, Derivative});
	end;

	self.Length, self.LengthIndeces = Length, Sums;
end

--[=[
	@param t number

	Returns the Vector3 point at the given t value (t must be between 0 and 1 to return an excpected value)
	does not work if the bezier does not have any points attached to it
]=]
function BezierTween:CalculatePositionAt(t)
	SmartAssert(type(t) == "number", `Bezier:CalculatePositionAt() only accepts a number, got {tostring(t)}!`);

	local Points = self.Points;
	local NumberOfPoints = #Points;

	SmartAssert(NumberOfPoints > 0, "Bezier:CalculatePositionAt() only works if there is at least 1 BezierPoint!");

	local AllPoints = self:GetAllPoints();
	return deCasteljau(AllPoints, t);
end

--[=[
	@param t number

	Returns the Vector3 point at the given t value, where t is relative to the length of the Bezier curve
	does not work if the bezier does not have any points attached to it
]=]
function BezierTween:CalculatePositionRelativeToLength(t)
	SmartAssert(type(t) == "number", `Bezier:CalculatePositionRelativeToLength() only accepts a number, got {tostring(t)}!`);

	local Points = self.Points;
	local NumberOfPoints = #Points;

	SmartAssert(NumberOfPoints > 0, "Bezier:CalculatePositionRelativeToLength() only works if there is at least 1 BezierPoint!");

	local Length = self.Length;
	local LengthIndeces = self.LengthIndeces;
	local AllPoints = self:GetAllPoints();

	if (#AllPoints > 1) then
		local TargetLength = Length * t;
		local NearestParameterIndex, NearestParameter;

		for Index, OrderedPair in ipairs(LengthIndeces) do
			if (TargetLength - OrderedPair[2] <= 0) then
				NearestParameterIndex = Index;
				NearestParameter = OrderedPair;
				break;
			elseif (Index == #LengthIndeces) then
				NearestParameterIndex = Index;
				NearestParameter = OrderedPair;
				break;
			end;
		end;

		local p0, p1;
		if (LengthIndeces[NearestParameterIndex - 1]) then
			p0, p1 = self:CalculatePositionAt(LengthIndeces[NearestParameterIndex - 1][1]), self:CalculatePositionAt(NearestParameter[1]);
		else
			p0, p1 = self:CalculatePositionAt(NearestParameter[1]), self:CalculatePositionAt(LengthIndeces[NearestParameterIndex + 1][1]);
		end;

		local PercentError = (NearestParameter[2] - TargetLength) / (p1 - p0).Magnitude;
		return p0 + (p1 - p0) * (1 - PercentError);
	else
		return self:CalculatePositionAt(0);
	end;
end

--[=[
	@param t number

	Returns the tangent vector in the direction of the path made by the bezier at t
	in order to get a derivative of a Bezier, you need at least 2 points in the Bezier
]=]
function BezierTween:CalculateDerivativeAt(t)
	SmartAssert(type(t) == "number", `Bezier:CalculateDerivativeAt() only accepts a number, got {tostring(t)}!`);

	local Points = self.Points;
	local NumberOfPoints = #Points;

	SmartAssert(NumberOfPoints > 1, "Bezier:CalculateDerivativeAt() only works if there are at least 2 BezierPoints!");

	local AllPoints = self:GetAllPoints();
	return deCasteljauDerivative(AllPoints, t);
end

--[=[
	@param t number

	Returns the tangent vector in the direction of the path made by the bezier at t (where t is relative to the length of the Bezier Curve)
	does not work if the bezier does not have at least 2 points
	the given t value must be between 0 and 1
]=]
function BezierTween:CalculateDerivativeRelativeToLength(t)
	SmartAssert(type(t) == "number", `Bezier:CalculateDerivativeRelativeToLength() only accepts a number, got {tostring(t)}!`);

	local Points = self.Points;
	local NumberOfPoints = #Points;

	SmartAssert(NumberOfPoints > 1, "Bezier:CalculateDerivativeRelativeToLength() only works if there are at least 2 BezierPoints!");

	local Length = self.Length;
	local LengthIndeces = self.LengthIndeces;
	local TargetLength = Length * t;
	local NearestParameterIndex, NearestParameter;

	for Index, OrderedPair in ipairs(LengthIndeces) do
		if (TargetLength - OrderedPair[2] <= 0) then
			NearestParameterIndex = Index;
			NearestParameter = OrderedPair;
			break;
		elseif (Index == #LengthIndeces) then
			NearestParameterIndex = Index;
			NearestParameter = OrderedPair;
			break;
		end;
	end;

	local d0, d1;
	if (LengthIndeces[NearestParameterIndex - 1]) then
		d0, d1 = self:CalculateDerivativeAt(LengthIndeces[NearestParameterIndex - 1][1]), self:CalculateDerivativeAt(NearestParameter[1]);
	else
		d0, d1 = self:CalculateDerivativeAt(NearestParameter[1]), self:CalculateDerivativeAt(LengthIndeces[NearestParameterIndex + 1][1]);
	end;

	local PercentError = (NearestParameter[2] - TargetLength) / (d1 - d0).Magnitude;
	return d0 + (d1 - d0) * (1 - PercentError);
end

--[=[
	@param object {any}
	@param propertyTable {any}
	@param t number
	@param relativeToLength boolean?

	Applies the tween to the given object
]=]
function BezierTween:_applyTween(object: {any}, propertyTable: {any}, t: number, relativeToLength: boolean?)
	for _, PropertName in propertyTable do
		local PropertyType = typeof(object[PropertName]);
		local Position = relativeToLength and self:CalculatePositionRelativeToLength(t) or self:CalculatePositionAt(t);

		if (PropertyType == "number" or PropertyType == "Vector2" or PropertyType == "Vector3") then
			object[PropertName] = Position;
		elseif (PropertyType == "CFrame") then
			local Derivative = relativeToLength and self:CalculateDerivativeRelativeToLength(t) or self:CalculateDerivativeAt(t);
			object[PropertName] = CFrame.lookAt(Position, Position + Derivative);
		else
			warn(`Attempt to apply a BezierTween to a property of type {typeof(object[PropertName])}!`);
		end;
	end;
end

--[=[
	@param object Instance | table
	@param propertyTable {any}
	@param bezierTweenInfo TweenInfo
	@param relativeToLength boolean?

	Tweens a given object in the path made by the Bezier (cframe version)
	works for any object that has the properties given by the property table
]=]
function BezierTween:CreateTween(object, propertyTable, tweenInfo, relativeToLength)
	SmartAssert(#self.Points > 1, "Bezier:CreateTween() only works if there are at least 2 BezierPoints in the Bezier!");

	-- Check if the given properties exist inside the given object
	for _, PropertyName in propertyTable do
		SmartAssert(ValidPropertyName(object, PropertyName), "Bezier:CreateTween() Cannot find the given properties inside the given object!");
	end;

	tweenInfo = tweenInfo or TweenInfo.new(
		DEFAULT_TWEEN_TIME,
		DEFAULT_TWEEN_EASING_STYLE,
		DEFAULT_TWEEN_EASING_DIRECTION,
		DEFAULT_TWEEN_REPEAT_COUNT,
		DEFAULT_TWEEN_REVERSES,
		DEFAULT_TWEEN_DELAY
	);

	local NumberValue = Instance.new("NumberValue");
	local Tween = TweenService:Create(NumberValue, tweenInfo, {Value = 1});

	NumberValue:GetPropertyChangedSignal("Value"):Connect(function()
		self:_applyTween(object, propertyTable, NumberValue.Value, relativeToLength);
	end);

	Tween.Destroying:Once(function()
		self._trove:Remove(NumberValue);
		NumberValue:Destroy();
	end);

	self._trove:Add(NumberValue);
	return Tween;
end

--[=[
	Destroys the Bezier
]=]
function BezierTween:Destroy()
	-- Disconnect all connections
	for Point, PointTrove in self._pointConnections do
		PointTrove:Clean();
		self._pointConnections[Point] = nil;
	end;

	-- Clean the trove
	self._trove:Clean();

	-- Destroy the metatable
	setmetatable(self, nil);
end

-- Make indexing the class with the wrong key throw an error
setmetatable(BezierTween, {
	__index = function(_, key)
		print(key);
		error(`Attempt to get Bezier:{tostring(key)} (not a valid member)`, 2);
	end,
	__newindex = function(_, key, _)
		error(`Attempt to set Bezier:{tostring(key)} (not a valid member)`, 2);
	end
});

return table.freeze({
	new = BezierTween.new,
	AddBezierPoint = BezierTween.AddBezierPoint,
	ChangeBezierPoint = BezierTween.ChangeBezierPoint,
	GetAllPoints = BezierTween.GetAllPoints,
	GetPoint = BezierTween.GetPoint,
	RemoveBezierPoint = BezierTween.RemoveBezierPoint,
	CalculatePositionAt = BezierTween.CalculatePositionAt,
	CalculatePositionRelativeToLength = BezierTween.CalculatePositionRelativeToLength,
	CalculateDerivativeAt = BezierTween.CalculateDerivativeAt,
	CalculateDerivativeRelativeToLength = BezierTween.CalculateDerivativeRelativeToLength,
	CreateTween = BezierTween.CreateTween,
	Destroy = BezierTween.Destroy,
});
