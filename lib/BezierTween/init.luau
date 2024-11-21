--!nocheck
local TweenService = game:GetService("TweenService");

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
	@field _pointConnections {[Instance]: {["UpdateLengthChanged"]: RBXScriptConnection?, ["AncestryChanged"]: RBXScriptConnection?}}
	@field _connections {[string]: RBXScriptConnection?}
	@field _instances {[Instance]: Instance?}
]=]
export type BezierTweenArguments = {
	Points: {BezierPoint},
	LengthIterations: number,
	LengthIndeces: {[number]: {number}},
	Length: number,
	_pointConnections: {[Instance]: {["UpdateLengthChanged"]: RBXScriptConnection?, ["AncestryChanged"]: RBXScriptConnection?}},
	_connections: {[string]: RBXScriptConnection?},
	_instances: {[Instance]: Instance?},
}

--[=[
	@within BezierTween
	@interface Object
	@field AddBezierPoint (self: BezierTween, point: Vector3 | BasePart, index: number?) -> ()
	@field ChangeBezierPoint (self: BezierTween, index: number, point: Vector3 | BasePart) -> ()
	@field GetAllPoints (self: BezierTween) -> {Vector3}
	@field GetPoint (self: BezierTween, i: number) -> Vector3?
	@field RemoveBezierPoint (self: BezierTween, index: number) -> ()
	@field UpdateLength (self: BezierTween) -> ()
	@field CalculatePositionAt (self: BezierTween, t: number) -> Vector3
	@field CalculatePositionRelativeToLength (self: BezierTween, t: number) -> Vector3
	@field CalculateDerivativeAt (self: BezierTween, t: number) -> Vector3?
	@field CalculateDerivativeRelativeToLength (self: BezierTween, t: number) -> Vector3
	@field CreateVector3Tween (self: BezierTween, object: Instance | {[any]: any}, propertyTable: {any}, bezierTweenInfo: TweenInfo, RelativeToLength: boolean?) -> Tween
	@field CreateCFrameTween (self: BezierTween, object: Instance | {[any]: any}, propertyTable: {any}, bezierTweenInfo: TweenInfo, RelativeToLength: boolean?) -> Tween
	@field Destroy (self: BezierTween) -> ()
	@field new ({Vector3 | BasePart}) -> BezierTween
]=]
type Object = {
	__index: Object,
	AddBezierPoint: (self: BezierTween, point: Vector3 | BasePart, index: number?) -> (),
	ChangeBezierPoint: (self: BezierTween, index: number, point: Vector3 | BasePart) -> (),
	GetAllPoints: (self: BezierTween) -> {Vector3},
	GetPoint: (self: BezierTween, i: number) -> Vector3?,
	RemoveBezierPoint: (self: BezierTween, index: number) -> (),
	UpdateLength: (self: BezierTween) -> (),
	CalculatePositionAt: (self: BezierTween, t: number) -> Vector3,
	CalculatePositionRelativeToLength: (self: BezierTween, t: number) -> Vector3,
	CalculateDerivativeAt: (self: BezierTween, t: number) -> Vector3?,
	CalculateDerivativeRelativeToLength: (self: BezierTween, t: number) -> Vector3,
	CreateVector3Tween: (self: BezierTween, object: Instance | {[any]: any}, propertyTable: {any}, bezierTweenInfo: TweenInfo, RelativeToLength: boolean?) -> Tween,
	CreateCFrameTween: (self: BezierTween, object: Instance | {[any]: any}, propertyTable: {any}, bezierTweenInfo: TweenInfo, RelativeToLength: boolean?) -> Tween,
	Destroy: (self: BezierTween) -> (),
	new: ({Vector3 | BasePart}) -> BezierTween,
}

--[=[
	@class BezierTween
]=]
local BezierTween: Object = {} :: Object;
BezierTween.__index = BezierTween;

-- Bernstein Polynomial (used in position and derivative functions)
function B(n: number, i: number, t: number): number
	local function Factorial(num: number): number
		if (num == 0) then
			return 1;
		else
			return num * Factorial(num - 1);
		end;
	end;

	return (Factorial(n) / (Factorial(i) * Factorial(n - i))) * t^(i) * (1 - t)^(n - i);
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
	self._connections = {};
	self._instances = {};

	for _, Point in pairs({...}) do
		if (typeof(Point) == "Vector3" or (typeof(Point) == "Instance" and Point:IsA("BasePart"))) then
			self:AddBezierPoint(Point);
		else
			error("The Bezier.new() constructor only takes in Vector3s and BaseParts as inputs!");
		end;
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
	if (point and (typeof(point) == "Instance" and point:IsA("BasePart")) or typeof(point) == "Vector3") then
		local NewPoint: BezierPoint = {
			Type = typeof(point) == "Vector3" and "StaicPoint" or "BasePartPoint";
			Point = point;
		};

		-- Watch for removal or changes
		if (NewPoint.Type == "BasePartPoint") then
			if (not self._pointConnections[point]) then
				self._pointConnections[point] = {
					["UpdateLengthChanged"] = nil,
					["AncestryChanged"] = nil
				};
			end;

			local PointConnections = self._pointConnections[point];

			PointConnections["UpdateLengthChanged"] = (point:: BasePart).Changed:Connect(function(prop)
				if (prop == "Position") then
					self:UpdateLength();
				end;
			end);

			PointConnections["AncestryChanged"] = (point:: BasePart).AncestryChanged:Connect(function(_, parent)
				if (parent == nil) then
					local pointIndex = table.find(self.Points, NewPoint);

					if (pointIndex) then
						table.remove(self.Points, pointIndex);
					end;

					PointConnections["AncestryChanged"]:Disconnect();
					PointConnections["UpdateLengthChanged"]:Disconnect();
				end;
			end);
		end;

		if (index and type(index) == "number") then
			table.insert(self.Points, index, NewPoint);
		elseif (not index) then
			table.insert(self.Points, NewPoint);
		elseif (type(index) ~= "number") then
			error("Bezier:AddBezierPoint() only accepts an integer as the second argument!");
		end;

		self:UpdateLength();
	else
		error("Bezier:AddBezierPoint() only accepts a Vector3 or BasePart as the first argument!");
	end;
end

--[=[
	@param index number
	@param p Vector3 | BasePart

	Changes a BezierPoint in the Bezier
	only works if the BezierPoint exists in the Bezier
]=]
function BezierTween:ChangeBezierPoint(index, point)
	if (type(index) ~= "number") then
		error("Bezier:ChangeBezierPoint() only accepts a number index as the first argument!");
	end;

	if (point and (typeof(point) == "Instance" and point:IsA("BasePart")) or typeof(point) == "Vector3") then
		local BezierPoint = self.Points[index];

		if (BezierPoint) then
			BezierPoint.Type = typeof(point) == "Vector3" and "StaicPoint" or "BasePartPoint";
			BezierPoint.Point = point;
			self:UpdateLength();
		else
			error("Did not find BezierPoint at index " .. tostring(index));
		end;
	else
		error("Bezier:ChangeBezierPoint() only accepts a Vector3 or BasePart as the second argument!");
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
		table.insert(NewPoints, self:GetPoint(Index));
	end;

	return NewPoints;
end

--[=[
	@param i number

	Gets the BezierPoint of the Bezier at the index
]=]
function BezierTween:GetPoint(i)
	local Points = self.Points;

	if (Points[i]) then
		return typeof(Points[i].Point) == "Vector3" and Points[i].Point or Points[i].Point.Position;
	else
		error("Did not find a BezierPoint at index " .. tostring(i) .. "!");
	end;
end

--[=[
	@param index number

	Removes a BezierPoint from the Bezier
]=]
function BezierTween:RemoveBezierPoint(index)
	if (self.Points[index]) then
		local Point = table.remove(self.Points, index);

		if (typeof(Point.Point) == "Instance" and Point.Point:IsA("BasePart")) then
			for _, Connection in self._pointConnections[Point.Point] do
				if (Connection.Connected) then
					Connection:Disconnect();
				end;
			end;

			self._pointConnections[Point.Point] = nil;
		end;

		self:UpdateLength();
	end;
end

--[=[
	@return (number, {{number, number, number}, {number, number, number}})

	Updates length of the Bezier
]=]
function BezierTween:UpdateLength()
	local Points = self:GetAllPoints();
	local Iterations = self.LengthIterations;

	if (#Points < 2) then
		return 0, {{0, 0, 0}, {0, 0, 0}};
	end;

	local Length = 0;
	local SUMS = {};

	for Index = 1, Iterations do
		local Derivative = self:CalculateDerivativeAt((Index - 1) / (Iterations - 1));
		Length += Derivative.Magnitude * (1 / Iterations);
		table.insert(SUMS, {((Index - 1) / (Iterations - 1)), Length, Derivative});
	end;

	self.Length, self.LengthIndeces = Length, SUMS;
end

--[=[
	@param t number

	Returns the Vector3 point at the given t value (t must be between 0 and 1 to return an excpected value)
	does not work if the bezier does not have any points attached to it
]=]
function BezierTween:CalculatePositionAt(t)
	if (type(t) ~= "number") then
		error("Bezier:CalculatePositionAt() only accepts a number, got " .. tostring(t) .. "!");
	end;

	local Points = self.Points;
	local NumberOfPoints = #Points;

	if (NumberOfPoints > 0) then
		local AllPoints = self:GetAllPoints();
		local NumberOfAllPoints = #AllPoints;

		local c_t do
			c_t = Vector3.new();

			for Index = 1, NumberOfAllPoints do
				local p_i = AllPoints[Index];
				local B_nit = B(NumberOfAllPoints - 1, Index - 1, t);
				c_t += B_nit * p_i;
			end;
		end;

		return c_t;
	else
		error("Bezier:CalculatePositionAt() only works if there is at least 1 BezierPoint!");
	end;
end

--[=[
	@param t number

	Returns the Vector3 point at the given t value, where t is relative to the length of the Bezier curve
	does not work if the bezier does not have any points attached to it
]=]
function BezierTween:CalculatePositionRelativeToLength(t)
	if (type(t) ~= "number") then
		error("Bezier:CalculatePositionRelativeToLength() only accepts a number, got " .. tostring(t) .. "!");
	end;

	local Points = self.Points;
	local NumberOfPoints = #Points;

	if (NumberOfPoints > 0) then
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
	else
		error("Bezier:CalculatePositionRelativeToLength() only works if there is at least 1 BezierPoint!");
	end;
end

--[=[
	@param t number

	Returns the tangent vector in the direction of the path made by the bezier at t
	in order to get a derivative of a Bezier, you need at least 2 points in the Bezier
]=]
function BezierTween:CalculateDerivativeAt(t)
	if (type(t) ~= "number") then
		error("Bezier:CalculateDerivativeAt() only accepts a number, got " .. tostring(t) .. "!");
	end;

	local Points = self.Points;
	local NumberOfPoints = #Points;

	if (NumberOfPoints > 1) then
		local AllPoints = self:GetAllPoints();
		local NumberOfAllPoints = #AllPoints;

		local cPrime_t do
			cPrime_t = Vector3.new();

			for Index = 1, NumberOfAllPoints - 1 do
				local p_i1, p_i = AllPoints[Index + 1], AllPoints[Index];
				local Q_i = (NumberOfAllPoints - 1) * (p_i1 - p_i);
				local B_mit = B(NumberOfAllPoints - 2, Index - 1, t);
				cPrime_t += B_mit * Q_i;
			end;
		end;

		return cPrime_t;
	else
		error("Bezier:CalculateDerivativeAt() only works if there are at least 2 BezierPoints!");
	end;
end

--[=[
	@param t number

	Returns the tangent vector in the direction of the path made by the bezier at t (where t is relative to the length of the Bezier Curve)
	does not work if the bezier does not have at least 2 points
	the given t value must be between 0 and 1
]=]
function BezierTween:CalculateDerivativeRelativeToLength(t)
	if (type(t) ~= "number") then
		error("Bezier:CalculateDerivativeRelativeToLength() only accepts a number, got " .. tostring(t) .. "!");
	end;

	local Points = self.Points;
	local NumberOfPoints = #Points;

	if (NumberOfPoints > 1) then
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
	else
		error("Bezier:CalculateDerivativeRelativeToLength() only works if there are at least 2 BezierPoints!");
	end;
end

--[=[
	@param object Instance | table
	@param propertyTable {any}
	@param bezierTweenInfo TweenInfo
	@param RelativeToLength boolean?

	Tweens a given object in the path made by the Bezier (position only)
	works for any object that has the properties given by the property table
]=]
function BezierTween:CreateVector3Tween(object, propertyTable, bezierTweenInfo, RelativeToLength)
	if (#self.Points == 0) then
		error("Bezier:CreateVector3Tween() only works if there is at least 1 BezierPoint in the Bezier!");
	end;

	if (typeof(object) ~= "Instance" and typeof(object) ~= "table") then
		error("Bezier:CreateVector3Tween() requires an Instance or a table as the first argument!");
	end;

	if (not (typeof(bezierTweenInfo) == "TweenInfo")) then
		error("Bezier:CreateVector3Tween() requires a TweenInfo object as the third argument!");
	end;

	local Success, FoundProperties = pcall(function()
		local Found = true;

		for _, Name in propertyTable do
			if (typeof(object[Name]) ~= "Vector3" and typeof(object[Name]) ~= "nil") then
				Found = false;
				break;
			end;
		end;

		return Found;
	end);

	if (Success and FoundProperties) then
		local NumberValue = Instance.new("NumberValue");
		local Tween = TweenService:Create(NumberValue, bezierTweenInfo, {Value = 1});

		Tween.Changed:Connect(function(prop)
			if (prop == "PlaybackState") then
				local PlaybackState = Tween.PlaybackState;

				if (PlaybackState == Enum.PlaybackState.Playing) then
					self._connections["Vector3Tween"] = NumberValue.Changed:Connect(function(t)
						for _, PropertyName in propertyTable do
							object[PropertyName] = RelativeToLength and self:CalculatePositionRelativeToLength(t) or self:CalculatePositionAt(t);
						end;
					end);
				else
					if (self._connections["Vector3Tween"]) then
						self._connections["Vector3Tween"]:Disconnect();
					end;
				end;
			end;
		end);

		table.insert(self._instances, NumberValue);
		return Tween;
	else
		error("Bezier:CreateVector3Tween() requires a matching property table with Vector3 or nil property names for the object as the second argument!");
	end;
end

--[=[
	@param object Instance | table
	@param propertyTable {any}
	@param bezierTweenInfo TweenInfo
	@param RelativeToLength boolean?

	Tweens a given object in the path made by the Bezier (cframe version)
	works for any object that has the properties given by the property table
]=]
function BezierTween:CreateCFrameTween(object, propertyTable, bezierTweenInfo, RelativeToLength)
	if (#self.Points <= 1) then
		error("Bezier:CreateVector3Tween() only works if there are at least 2 BezierPoints in the Bezier!");
	end;

	if (typeof(object) ~= "Instance" and typeof(object) ~= "table") then
		error("Bezier:CreateCFrameTween() requires an Instance or a table as the first argument!");
	end;

	if (not (typeof(bezierTweenInfo) == "TweenInfo")) then
		error("Bezier:CreateCFrameTween() requires a TweenInfo object as the third argument!");
	end;

	local Success, FoundProperties = pcall(function()
		local Found = true;

		for _, Name in propertyTable do
			if (typeof(object[Name]) ~= "CFrame" and typeof(object[Name]) ~= "nil") then
				Found = false;
				break;
			end;
		end;

		return Found;
	end);

	if (Success and FoundProperties) then
		local NumberValue = Instance.new("NumberValue");
		local Tween = TweenService:Create(NumberValue, bezierTweenInfo, {Value = 1});

		Tween.Changed:Connect(function(prop)
			if (prop == "PlaybackState") then
				local PlaybackState = Tween.PlaybackState;

				if (PlaybackState == Enum.PlaybackState.Playing) then
					self._connections["CFrameTween"] = NumberValue.Changed:Connect(function(t)
						for _, PropertyName in propertyTable do
							local Position = RelativeToLength and self:CalculatePositionRelativeToLength(t) or self:CalculatePositionAt(t);
							local Derivative = RelativeToLength and self:CalculateDerivativeRelativeToLength(t) or self:CalculateDerivativeAt(t);
							object[PropertyName] = CFrame.new(Position, Position + Derivative);
						end;
					end);
				else
					if (self._connections["CFrameTween"]) then
						self._connections["CFrameTween"]:Disconnect();
					end;
				end;
			end;
		end);

		table.insert(self._instances, NumberValue);
		return Tween;
	else
		error("Bezier:CreateCFrameTween() requires a matching property table with CFrame or nil property names for the object as the second argument!");
	end;
end

--[=[
	Destroys the Bezier
]=]
function BezierTween:Destroy()
	-- Disconnect all connections
	for Point, Connections in self._pointConnections do
		if (Connections["AncestryChanged"]) then
			Connections["AncestryChanged"]:Disconnect();
		end;

		if (Connections["UpdateLengthChanged"]) then
			Connections["UpdateLengthChanged"]:Disconnect();
		end;

		self._pointConnections[Point] = nil;
	end;

	-- Disconnect all tween listener connections
	for _, Connection in self._connections do
		if (Connection) then
			Connection:Disconnect();
		end;
	end;

	-- Destroy all instances
	for _, Object in self._instances do
		if (Object) then
			Object:Destroy();
		end;
	end;

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
	end,
})

return table.freeze({
	new = BezierTween.new,
	AddBezierPoint = BezierTween.AddBezierPoint,
	ChangeBezierPoint = BezierTween.ChangeBezierPoint,
	GetAllPoints = BezierTween.GetAllPoints,
	GetPoint = BezierTween.GetPoint,
	RemoveBezierPoint = BezierTween.RemoveBezierPoint,
	UpdateLength = BezierTween.UpdateLength,
	CalculatePositionAt = BezierTween.CalculatePositionAt,
	CalculatePositionRelativeToLength = BezierTween.CalculatePositionRelativeToLength,
	CalculateDerivativeAt = BezierTween.CalculateDerivativeAt,
	CalculateDerivativeRelativeToLength = BezierTween.CalculateDerivativeRelativeToLength,
	CreateVector3Tween = BezierTween.CreateVector3Tween,
	CreateCFrameTween = BezierTween.CreateCFrameTween,
	Destroy = BezierTween.Destroy,
})
